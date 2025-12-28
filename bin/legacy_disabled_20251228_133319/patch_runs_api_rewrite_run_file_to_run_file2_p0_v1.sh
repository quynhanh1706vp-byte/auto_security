#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_rewrite_runfile2_${TS}"
echo "[BACKUP] ${F}.bak_rewrite_runfile2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_REWRITE_RUN_FILE_TO_RUN_FILE2_P0_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Add a tiny after_request that runs LAST (declared at end), to rewrite JSON body for /api/vsp/runs.
inject = r'''
# =========================
# VSP_REWRITE_RUN_FILE_TO_RUN_FILE2_P0_V1
# Force rewrite any /api/vsp/run_file? -> /api/vsp/run_file2? inside /api/vsp/runs JSON response.
# =========================
try:
    from flask import request as _rq_last
except Exception:
    _rq_last = None  # type: ignore

try:
    _app_last = app  # noqa: F821
except Exception:
    _app_last = None

if _app_last is not None and getattr(_app_last, "after_request", None) is not None:
    @_app_last.after_request
    def _vsp_after_rewrite_runfile2(resp):
        try:
            if not _rq_last or _rq_last.path != "/api/vsp/runs":
                return resp
            ct = (resp.headers.get("Content-Type","") or "")
            if "application/json" not in ct:
                return resp
            body = resp.get_data(as_text=True) or ""
            if "/api/vsp/run_file?" not in body:
                return resp
            body2 = body.replace("/api/vsp/run_file?","/api/vsp/run_file2?")
            resp.set_data(body2)
            resp.headers["Content-Length"] = str(len(body2.encode("utf-8")))
            return resp
        except Exception:
            return resp
# =========================
# END VSP_REWRITE_RUN_FILE_TO_RUN_FILE2_P0_V1
# =========================
'''
p.write_text(s.rstrip()+"\n"+inject+"\n", encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== verify json_path now points to run_file2 =="
curl -sS "http://127.0.0.1:8910/api/vsp/runs?limit=1" | python3 - <<'PY'
import sys,json
d=json.load(sys.stdin)
it=(d.get("items") or [{}])[0]
print("run_id=", it.get("run_id"))
print("json_path=", (it.get("has") or {}).get("json_path"))
PY
