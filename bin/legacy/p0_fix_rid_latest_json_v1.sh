#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_ridlatest_${TS}"
echo "[BACKUP] ${WSGI}.bak_ridlatest_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RID_LATEST_JSON_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

patch_block = textwrap.dedent(r'''
# ===================== {MARK} =====================
# Contract: /api/vsp/rid_latest MUST always return JSON (never HTML/empty)
# Picks latest RID by scanning run output dirs (out/out_ci) by mtime.

from pathlib import Path as _VspPath
import time as _vsp_time
try:
    from flask import jsonify as _vsp_jsonify, make_response as _vsp_make_response
except Exception:
    _vsp_jsonify = None
    _vsp_make_response = None

def _vsp_pick_latest_rid_fs():
    try:
        base = _VspPath(__file__).resolve().parent  # ui/
        root = base.parent                           # SECURITY_BUNDLE/
        candidates = [
            root / "out",
            root / "out_ci",
            base / "out",
            base / "out_ci",
            _VspPath("/home/test/Data/SECURITY_BUNDLE/out"),
            _VspPath("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        ]
        best = None  # (mtime, rid)
        for d in candidates:
            if not d.exists() or not d.is_dir():
                continue
            for sub in d.iterdir():
                if not sub.is_dir():
                    continue
                name = sub.name
                # accept common RID prefixes
                if not (name.startswith("VSP_") or name.startswith("RUN_") or "VSP_CI_" in name):
                    continue
                # validate by presence of gate/summary or reports folder
                ok = False
                for rel in ("run_gate_summary.json", "reports/run_gate_summary.json", "report/run_gate_summary.json"):
                    if (sub / rel).exists():
                        ok = True
                        break
                if not ok:
                    # still allow if it has reports/ or findings_unified.json
                    if (sub / "reports").exists() or (sub / "findings_unified.json").exists() or (sub / "reports/findings_unified.json").exists():
                        ok = True
                if not ok:
                    continue
                try:
                    mt = sub.stat().st_mtime
                except Exception:
                    mt = 0
                rid = name
                if (best is None) or (mt > best[0]):
                    best = (mt, rid)
        return best[1] if best else ""
    except Exception:
        return ""

def _vsp_json(obj, status=200):
    # Flask jsonify when available; otherwise plain JSON string.
    try:
        if _vsp_jsonify and _vsp_make_response:
            resp = _vsp_make_response(_vsp_jsonify(obj), status)
            resp.headers["Cache-Control"] = "no-store"
            return resp
    except Exception:
        pass
    import json
    body = json.dumps(obj, ensure_ascii=False)
    try:
        return (body, status, {"Content-Type":"application/json; charset=utf-8", "Cache-Control":"no-store"})
    except Exception:
        return body

# If route exists -> replace handler body; else add new route.
''').strip("\n").format(MARK=MARK) + "\n"

# Ensure patch block is present once (place near imports top, but safe to append after app defined too)
# We'll append near end; then patch/replace route handler.
if MARK not in s:
    s = s + "\n\n" + patch_block + "\n"

# Replace existing rid_latest route if present
route_pat = re.compile(r'@app\.route\(\s*[\'"]/api/vsp/rid_latest[\'"]\s*\)\s*\n'
                       r'def\s+\w+\s*\([^)]*\)\s*:\s*\n'
                       r'(?:[ \t].*\n)+', re.M)

new_handler = textwrap.dedent(f'''
@app.route("/api/vsp/rid_latest")
def vsp_rid_latest():
    rid = ""
    via = ""
    try:
        rid = _vsp_pick_latest_rid_fs()
        via = "fs"
    except Exception:
        rid = ""
        via = "err"
    ok = bool(rid)
    return _vsp_json({{"ok": ok, "rid": rid, "via": via, "ts": int(_vsp_time.time())}}, 200)
''').lstrip("\n")

if route_pat.search(s):
    s = route_pat.sub(new_handler, s, count=1)
else:
    s = s + "\n\n" + new_handler + "\n"

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched:", MARK)
PY

echo "== [verify] curl rid_latest (raw) =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS "$BASE/api/vsp/rid_latest" || true
echo
echo "== [restart] service =="
systemctl restart "$SVC" 2>/dev/null || true
systemctl is-active "$SVC" 2>/dev/null && echo "[OK] $SVC active" || true
