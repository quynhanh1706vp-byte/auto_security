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
  cp -f "$f" "${f}.bak_vmanifest_safe_v5_${TS}"
  echo "[BACKUP] ${f}.bak_vmanifest_safe_v5_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re, textwrap

# We will replace the injected block body with a SAFE try/except wrapper.
# We support both v3 and v4 marker names.
MARKERS = [
  "VSP_P0_VIRTUAL_MANIFEST_EVIDENCEINDEX_ALWAYS200_V3_INJECT",
  "VSP_P0_VIRTUAL_MANIFEST_EVIDENCEINDEX_DUALPATCH_V4_INJECT",
]

SAFE_BODY = r"""
# ===== __INJECT__ =====
try:
    _rid = request.args.get("rid", "") or request.args.get("RID", "")
    _path = request.args.get("path", "") or request.args.get("PATH", "")

    if _path in ("run_manifest.json", "run_evidence_index.json"):
        _gate_root_name = f"gate_root_{_rid}" if _rid else None
        _gate_root_path = _vsp_p0_try_resolve_gate_root_path(_rid, _gate_root_name) if "_vsp_p0_try_resolve_gate_root_path" in globals() else _vsp_try_resolve_gate_root_path(_rid, _gate_root_name)

        # Prefer real file if present
        if _gate_root_path:
            _real = _VSPPath(_gate_root_path) / _path
            if _real.is_file():
                try:
                    return send_file(str(_real))
                except Exception:
                    pass

        served_by = __file__ if "__file__" in globals() else "unknown"

        if _path == "run_manifest.json":
            if "_vsp_p0_virtual_manifest" in globals():
                payload = _vsp_p0_virtual_manifest(_rid, _gate_root_name, _gate_root_path, served_by)
            else:
                payload = _vsp_virtual_manifest(_rid, _gate_root_name, _gate_root_path)
                payload["served_by"] = served_by
        else:
            if "_vsp_p0_virtual_evidence_index" in globals():
                payload = _vsp_p0_virtual_evidence_index(_rid, _gate_root_name, _gate_root_path, served_by)
            else:
                payload = _vsp_virtual_evidence_index(_rid, _gate_root_name, _gate_root_path)
                payload["served_by"] = served_by

        return Response(json.dumps(payload, ensure_ascii=False, indent=2), status=200, mimetype="application/json")

except Exception as e:
    # P0: never 500. Return JSON with degraded=true, include error string for diagnosis.
    try:
        served_by = __file__ if "__file__" in globals() else "unknown"
    except Exception:
        served_by = "unknown"
    payload = {
        "ok": False,
        "generated": True,
        "degraded": True,
        "served_by": served_by,
        "err": f"{type(e).__name__}: {e}",
        "hint": "P0 SAFE MODE: set VSP_RUNS_ROOT(S) later to resolve gate_root_path; check server logs for full traceback.",
    }
    return Response(json.dumps(payload, ensure_ascii=False, indent=2), status=200, mimetype="application/json")
# ===== /__INJECT__ =====
""".strip("\n")

def patch_one(path: Path):
    s = path.read_text(encoding="utf-8", errors="replace")

    patched = False
    for mk in MARKERS:
        # Replace block between start/end markers for this mk
        # start: "# ===== <mk> =====" end: "# ===== /<mk> ====="
        pat = re.compile(
            r'^[ \t]*#\s*=====\s*' + re.escape(mk) + r'\s*=====\s*\n'
            r'(?:.*?\n)*?'
            r'^[ \t]*#\s*=====\s*/' + re.escape(mk) + r'\s*=====\s*$',
            re.M
        )
        m = pat.search(s)
        if not m:
            continue

        # Determine indentation from the matched start line
        start_line = s[m.start():].splitlines(True)[0]
        ind = re.match(r'^([ \t]*)', start_line).group(1)

        safe = SAFE_BODY.replace("__INJECT__", mk)
        safe = "\n".join((ind + ln) if ln else ln for ln in safe.split("\n"))

        s = s[:m.start()] + safe + s[m.end():]
        patched = True
        break

    if patched:
        path.write_text(s, encoding="utf-8")
    return patched

for fname in ("wsgi_vsp_ui_gateway.py", "vsp_demo_app.py"):
    ok = patch_one(Path(fname))
    print("[OK]" if ok else "[WARN]", "safe-wrap inject in", fname)
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke (expect JSON + HTTP=200) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("rid",""))' || true)"
echo "RID=$RID"
RID="${RID:-VSP_CI_20251219_092640}"

for p in run_manifest.json run_evidence_index.json; do
  echo "== $p =="
  curl -sS -H "Accept: application/json" -o "/tmp/vsp_${p}.out" -w "HTTP=%{http_code}\n" \
    "$BASE/api/vsp/run_file_allow?rid=${RID}&path=$p"
  head -n 25 "/tmp/vsp_${p}.out" | sed -e 's/\r$//'
done

echo "[DONE] If you still see HTML here, request is not reaching handler; otherwise JSON will show served_by/err."
