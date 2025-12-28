#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_findprev_guard_${TS}"
echo "[BACKUP] $F.bak_findprev_guard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "VSP_WSGI_FINDINGS_PREVIEW_SCHEMA_GUARD_V1"
if TAG in t:
    print("[OK] schema guard already installed, skip")
    raise SystemExit(0)

BLOCK = r'''

# === VSP_WSGI_FINDINGS_PREVIEW_SCHEMA_GUARD_V1 ===
def _vsp_findings_preview_guard_bytes(body_bytes: bytes) -> bytes:
    import json
    try:
        obj = json.loads(body_bytes.decode("utf-8", errors="ignore"))
        if not isinstance(obj, dict):
            return body_bytes

        # If endpoint returns missing-file -> degrade gracefully (commercial)
        if obj.get("ok") is False and obj.get("error") in ("findings_file_not_found",):
            rid = obj.get("rid")
            run_dir = obj.get("run_dir") or obj.get("run_dir_guess") or obj.get("run_dir_resolved") or obj.get("run_dir_path")
            fixed = {
                "ok": True,
                "has_findings": False,
                "warning": obj.get("error"),
                "rid": rid,
                "run_dir": run_dir,
                "file": None,
                "page": int(obj.get("page", 1) or 1),
                "limit": int(obj.get("limit", 200) or 200),
                "total": 0,
                "items": [],
                "facets": {"severity": {}, "tool": {}},
            }
            return json.dumps(fixed, ensure_ascii=False).encode("utf-8")

        return body_bytes
    except Exception:
        return body_bytes

def _vsp_wsgi_wrap_findings_preview_schema(app):
    if getattr(app, "_vsp_wrapped_findprev_guard", False):
        return app
    setattr(app, "_vsp_wrapped_findprev_guard", True)

    def _wrapped(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/vsp/run_findings_preview_v1/"):
            return app(environ, start_response)

        captured = {"status": None, "headers": None, "exc": None}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers) if headers else []
            captured["exc"] = exc_info
            return None

        iterable = app(environ, _sr)

        chunks = []
        try:
            for c in iterable:
                if c:
                    chunks.append(c)
        finally:
            try:
                close = getattr(iterable, "close", None)
                if close:
                    close()
            except Exception:
                pass

        body = b"".join(chunks)
        body2 = _vsp_findings_preview_guard_bytes(body)

        hdrs = captured["headers"] or []
        new_hdrs = []
        for k, v in hdrs:
            if str(k).lower() == "content-length":
                continue
            new_hdrs.append((k, v))
        new_hdrs.append(("Content-Length", str(len(body2))))
        start_response(captured["status"] or "200 OK", new_hdrs, captured["exc"])
        return [body2]

    return _wrapped

try:
    _APP = globals().get("application") or globals().get("app")
    if _APP is not None:
        globals()["application"] = _vsp_wsgi_wrap_findings_preview_schema(_APP)
except Exception:
    pass
# === /VSP_WSGI_FINDINGS_PREVIEW_SCHEMA_GUARD_V1 ===
'''

p.write_text(t + "\n" + BLOCK + "\n", encoding="utf-8")
print("[OK] appended findings preview schema guard (WSGI)")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile wsgi_vsp_ui_gateway.py"

bin/restart_8910_nosudo_force_v1.sh
echo "[DONE] schema guard installed + restarted."
