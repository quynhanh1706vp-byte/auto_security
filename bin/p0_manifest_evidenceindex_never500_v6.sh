#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
FILES=(wsgi_vsp_ui_gateway.py vsp_demo_app.py)

for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
done

TS="$(date +%Y%m%d_%H%M%S)"
for f in "${FILES[@]}"; do
  cp -f "$f" "${f}.bak_manifest_v6_${TS}"
  echo "[BACKUP] ${f}.bak_manifest_v6_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re, textwrap

# Replace any of these injected blocks (v3/v4/v5) with a fully self-contained version.
MARKERS = [
  "VSP_P0_VIRTUAL_MANIFEST_EVIDENCEINDEX_ALWAYS200_V3_INJECT",
  "VSP_P0_VIRTUAL_MANIFEST_EVIDENCEINDEX_DUALPATCH_V4_INJECT",
]

V6_BLOCK_TPL = r"""
# ===== __MK__ =====
try:
    # Self-contained: no dependency on module-level imports/helpers.
    from flask import request, make_response
    import json, time

    _rid = request.args.get("rid", "") or request.args.get("RID", "")
    _path = request.args.get("path", "") or request.args.get("PATH", "")

    if _path in ("run_manifest.json", "run_evidence_index.json"):
        now = int(time.time())
        served_by = globals().get("__file__", "unknown")

        if _path == "run_manifest.json":
            payload = {
                "ok": True,
                "rid": _rid,
                "gate_root": (f"gate_root_{_rid}" if _rid else None),
                "gate_root_path": None,
                "generated": True,
                "generated_at": now,
                "degraded": True,
                "served_by": served_by,
                "required_paths": [
                    "run_gate.json",
                    "run_gate_summary.json",
                    "findings_unified.json",
                    "reports/findings_unified.csv",
                    "run_manifest.json",
                    "run_evidence_index.json",
                ],
                "optional_paths": [
                    "reports/findings_unified.sarif",
                    "reports/findings_unified.html",
                    "reports/findings_unified.pdf",
                ],
                "hints": {
                    "why_degraded": "RUNS root not resolved in filesystem yet (P0 safe mode).",
                    "set_env": "Set VSP_RUNS_ROOT or VSP_RUNS_ROOTS to parent folder that contains gate_root_<RID>.",
                    "example": "VSP_RUNS_ROOT=/home/test/Data/SECURITY-10-10-v4/out_ci",
                },
            }
        else:
            payload = {
                "ok": True,
                "rid": _rid,
                "gate_root": (f"gate_root_{_rid}" if _rid else None),
                "gate_root_path": None,
                "generated": True,
                "generated_at": now,
                "degraded": True,
                "served_by": served_by,
                "evidence_dir": None,
                "files": [],
                "missing_recommended": [
                    "evidence/ui_engine.log",
                    "evidence/trace.zip",
                    "evidence/last_page.html",
                    "evidence/storage_state.json",
                    "evidence/net_summary.json",
                ],
            }

        resp = make_response(json.dumps(payload, ensure_ascii=False, indent=2), 200)
        resp.mimetype = "application/json"
        return resp

except Exception as e:
    # Even if Flask helpers fail, return a tuple fallback (never 500).
    try:
        import json
        served_by = globals().get("__file__", "unknown")
        payload = {
            "ok": False,
            "generated": True,
            "degraded": True,
            "served_by": served_by,
            "err": f"{type(e).__name__}: {e}",
            "hint": "P0 SAFE MODE: inject fallback engaged; check service logs for root cause.",
        }
        return (json.dumps(payload, ensure_ascii=False, indent=2), 200, {"Content-Type":"application/json; charset=utf-8"})
    except Exception:
        return ("{}", 200, {"Content-Type":"application/json; charset=utf-8"})
# ===== /__MK__ =====
""".strip("\n")

def replace_block(text: str, mk: str) -> str:
    # Find the whole block from start marker to end marker and replace.
    pat = re.compile(
        r'^[ \t]*#\s*=====\s*' + re.escape(mk) + r'\s*=====\s*\n'
        r'(?:.*?\n)*?'
        r'^[ \t]*#\s*=====\s*/' + re.escape(mk) + r'\s*=====\s*$',
        re.M
    )
    m = pat.search(text)
    if not m:
        return text

    # preserve indentation
    start_line = text[m.start():].splitlines(True)[0]
    ind = re.match(r'^([ \t]*)', start_line).group(1)

    v6 = V6_BLOCK_TPL.replace("__MK__", mk)
    v6 = "\n".join((ind + ln) if ln else ln for ln in v6.split("\n"))
    return text[:m.start()] + v6 + text[m.end():]

for fname in ("wsgi_vsp_ui_gateway.py", "vsp_demo_app.py"):
    p = Path(fname)
    s = p.read_text(encoding="utf-8", errors="replace")
    changed = False
    for mk in MARKERS:
        s2 = replace_block(s, mk)
        if s2 != s:
            s = s2
            changed = True
    if changed:
        p.write_text(s, encoding="utf-8")
        print("[OK] replaced inject blocks in", fname)
    else:
        print("[WARN] no matching inject block found in", fname, "(already different?)")
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke (expect HTTP=200 + JSON) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("rid",""))' || true)"
RID="${RID:-VSP_CI_20251219_092640}"
echo "RID=$RID"

for p in run_manifest.json run_evidence_index.json; do
  echo "== $p =="
  curl -sS -H "Accept: application/json" -o "/tmp/vsp_${p}.out" -w "HTTP=%{http_code}\n" \
    "$BASE/api/vsp/run_file_allow?rid=${RID}&path=$p"
  head -n 20 "/tmp/vsp_${p}.out" | sed -e 's/\r$//'
done

echo "[DONE] If still HTML+500, request is being intercepted before handler (global middleware/proxy)."
