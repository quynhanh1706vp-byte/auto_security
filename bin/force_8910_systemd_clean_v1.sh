#!/usr/bin/env bash
set -euo pipefail

SERVICE="vsp-ui-8910"
PORT="8910"

echo "== 1) stop systemd service =="
sudo systemctl stop "$SERVICE" 2>/dev/null || true

echo "== 2) kill ANY listener on :$PORT =="
# prefer fuser
sudo fuser -k "${PORT}/tcp" 2>/dev/null || true
# fallback: pkill common dev runs
pkill -f "python3 vsp_demo_app.py" 2>/dev/null || true
pkill -f "vsp_demo_app.py" 2>/dev/null || true
pkill -f "gunicorn.*:8910" 2>/dev/null || true

echo "== 3) show current listeners (should be empty) =="
sudo ss -ltnp | grep ":$PORT" || echo "[OK] no listener on :$PORT"

echo "== 4) rewrite wsgi_8910.py (healthz at WSGI layer) =="
cat > wsgi_8910.py <<'PY'
import os, json
os.environ.setdefault("VSP_UI_MODE", "PROD")

def _load_downstream_app():
    try:
        from vsp_demo_app import application as a  # type: ignore
        return a
    except Exception:
        pass
    try:
        from vsp_demo_app import app as a  # type: ignore
        return a
    except Exception:
        pass
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
        if (environ.get("PATH_INFO") or "") == "/healthz":
            body = json.dumps({"ok": True, "service": "vsp-ui-8910"}).encode("utf-8")
            start_response("200 OK", [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Content-Length", str(len(body))),
                ("Cache-Control", "no-store"),
            ])
            return [body]
        return self.app(environ, start_response)

application = HealthzMiddleware(_downstream)
PY

echo "== 5) restart systemd service =="
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE"

echo "== 6) verify listener + healthz =="
sudo ss -ltnp | grep ":$PORT" || true
curl -sS -D - http://127.0.0.1:${PORT}/healthz -o /dev/null | head -n 20
curl -sS http://127.0.0.1:${PORT}/healthz ; echo

echo "== 7) show service status (top) =="
sudo systemctl status "$SERVICE" --no-pager | sed -n '1,20p'
