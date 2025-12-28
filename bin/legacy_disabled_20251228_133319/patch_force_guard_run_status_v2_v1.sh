#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

if grep -q "VSP_RUN_STATUS_V2_GUARD_V1" "$F"; then
  echo "[OK] run_status_v2 guard already present, skip"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runstatusv2_guard_${TS}"
echo "[BACKUP] $F.bak_runstatusv2_guard_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

block = r"""
# === VSP_RUN_STATUS_V2_GUARD_V1 BEGIN ===
import json as _json
from datetime import datetime as _dt, timezone as _tz
import traceback as _tb

class VSPRunStatusV2GuardV1:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/vsp/run_status_v2/"):
            return self.app(environ, start_response)

        # normalize rid in PATH_INFO
        try:
            rid = path.split("/api/vsp/run_status_v2/", 1)[1]
        except Exception:
            rid = ""
        rid = (rid or "").strip()
        rid_norm = rid[4:] if rid.startswith("RUN_") else rid

        # rewrite path if needed
        if rid_norm != rid:
            environ = dict(environ)
            environ["PATH_INFO"] = "/api/vsp/run_status_v2/" + rid_norm

        try:
            return self.app(environ, start_response)
        except Exception as e:
            payload = {
                "ok": False,
                "status": "ERROR",
                "final": True,
                "http_code": 500,
                "error": "RUN_STATUS_V2_EXCEPTION_GUARDED",
                "rid": rid,
                "rid_norm": rid_norm,
                "detail": str(e),
                "ts_utc": _dt.now(_tz.utc).isoformat(),
            }
            body = _json.dumps(payload, ensure_ascii=False).encode("utf-8")
            hdrs = [
                ("Content-Type","application/json; charset=utf-8"),
                ("Content-Length", str(len(body))),
                ("Cache-Control","no-cache"),
                ("X-VSP-RUNSTATUSV2-MODE","GUARD_V1"),
            ]
            start_response("200 OK", hdrs)
            return [body]
# === VSP_RUN_STATUS_V2_GUARD_V1 END ===
"""

s += "\n" + block + "\n"

# Wrap application LAST (outermost), but keep existing wrappers by stacking
s += "\n# VSP_RUN_STATUS_V2_GUARD_V1 WRAP\napplication = VSPRunStatusV2GuardV1(application)\n"

p.write_text(s, encoding="utf-8")
print("[OK] appended guard middleware + wrapped application")
PY

python3 -m py_compile "$F"
echo "[OK] patched + py_compile OK => $F"
