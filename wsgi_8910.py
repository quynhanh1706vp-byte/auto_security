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
