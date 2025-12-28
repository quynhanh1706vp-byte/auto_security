#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

TS="$(date +%Y%m%d_%H%M%S)"

patch_append_mw(){
  local F="$1"
  [ -f "$F" ] || return 0

  if grep -q "VSP_P1_HEALTHZ_WSGIMW_V3" "$F"; then
    echo "[OK] already patched: $F"
    return 0
  fi

  cp -f "$F" "${F}.bak_healthz_wsgimw_${TS}"
  echo "[BACKUP] ${F}.bak_healthz_wsgimw_${TS}"

  python3 - <<PY
from pathlib import Path
p=Path("$F")
s=p.read_text(encoding="utf-8", errors="replace")

block = r'''

# --- VSP_P1_HEALTHZ_WSGIMW_V3 ---
# Hard intercept /healthz at WSGI layer to guarantee JSON (no template/redirect fallthrough).
def _vsp_healthz_wrap(_next_app):
    import json, os, time, socket
    def _app(environ, start_response):
        try:
            if environ.get("PATH_INFO") == "/healthz":
                payload = json.dumps({
                    "ui_up": True,
                    "ts": int(time.time()),
                    "pid": os.getpid(),
                    "host": socket.gethostname(),
                    "contract": "P1_HEALTHZ_V3"
                }).encode("utf-8")
                start_response("200 OK", [
                    ("Content-Type", "application/json; charset=utf-8"),
                    ("Cache-Control", "no-store"),
                    ("Content-Length", str(len(payload))),
                ])
                return [payload]
        except Exception:
            # fall through
            pass
        return _next_app(environ, start_response)
    return _app

try:
    # If Flask app exists, wrap its wsgi_app.
    if "app" in globals() and hasattr(app, "wsgi_app"):
        app.wsgi_app = _vsp_healthz_wrap(app.wsgi_app)
    # If gunicorn exports `application`, wrap it too.
    if "application" in globals() and callable(application):
        application = _vsp_healthz_wrap(application)
except Exception:
    pass
# --- /VSP_P1_HEALTHZ_WSGIMW_V3 ---

'''
p.write_text(s + block, encoding="utf-8")
print("[OK] appended WSGI healthz mw into", p)
PY

  python3 -m py_compile "$F" && echo "[OK] py_compile OK: $F"
}

# Patch the most likely gunicorn entrypoints
patch_append_mw "wsgi_vsp_ui_gateway.py"
patch_append_mw "vsp_demo_app.py"

echo "[OK] patched. Restart and verify:"
echo "  curl -i http://127.0.0.1:8910/healthz"
