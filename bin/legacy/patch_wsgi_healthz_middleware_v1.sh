#!/usr/bin/env bash
set -euo pipefail
F="wsgi_8910.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_wsgi_healthz_mw_${TS}"
echo "[BACKUP] $F.bak_wsgi_healthz_mw_${TS}"

cat > "$F" <<'PY'
"""
WSGI entrypoint for gunicorn.
Commercial-grade healthcheck:
- Intercept /healthz at WSGI layer (works even if downstream is not Flask)
"""
import os, json
os.environ.setdefault("VSP_UI_MODE", "PROD")

def _load_downstream_app():
    # 1) explicit application
    try:
        from vsp_demo_app import application as a  # type: ignore
        return a
    except Exception:
        pass
    # 2) app
    try:
        from vsp_demo_app import app as a  # type: ignore
        return a
    except Exception:
        pass
    # 3) factory
    try:
        from vsp_demo_app import create_app  # type: ignore
        return create_app()
    except Exception as e:
        raise RuntimeError("Cannot obtain downstream WSGI app from vsp_demo_app") from e

_downstream = _load_downstream_app()

class HealthzMiddleware:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path == "/healthz":
            body = json.dumps({"ok": True, "service": "vsp-ui-8910"}).encode("utf-8")
            headers = [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Content-Length", str(len(body))),
                ("Cache-Control", "no-store"),
            ]
            start_response("200 OK", headers)
            return [body]
        return self.app(environ, start_response)

application = HealthzMiddleware(_downstream)
PY

echo "[OK] wrote $F (WSGI healthz middleware)"
