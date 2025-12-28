#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fill8mw_${TS}"
echo "[BACKUP] $F.bak_fill8mw_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "VSP_WSGI_STATUSV2_FILL8_MW_V1"
if TAG in t:
    print("[OK] fill8 middleware already installed, skip")
    raise SystemExit(0)

BLOCK = r'''

# === VSP_WSGI_STATUSV2_FILL8_MW_V1 ===
def _vsp_statusv2_fill8_obj(obj: dict) -> dict:
    want = ["SEMGREP","TRIVY","KICS","GITLEAKS","CODEQL","BANDIT","SYFT","GRYPE"]
    try:
        rgs = obj.get("run_gate_summary") or {}
        by_tool = rgs.get("by_tool") or {}
        if not isinstance(by_tool, dict):
            by_tool = {}
        for k in want:
            if k not in by_tool:
                by_tool[k] = {"tool": k, "verdict": "NOT_RUN", "total": 0}
            else:
                v = by_tool.get(k)
                if isinstance(v, dict) and "tool" not in v:
                    v["tool"] = k
                    by_tool[k] = v
        rgs["by_tool"] = by_tool
        obj["run_gate_summary"] = rgs
    except Exception:
        pass
    return obj

def _vsp_statusv2_fill8_bytes(body_bytes: bytes) -> bytes:
    import json
    try:
        obj = json.loads(body_bytes.decode("utf-8", errors="ignore"))
        if isinstance(obj, dict) and obj.get("ok") is True and isinstance(obj.get("run_gate_summary"), dict):
            obj = _vsp_statusv2_fill8_obj(obj)
            return json.dumps(obj, ensure_ascii=False).encode("utf-8")
    except Exception:
        return body_bytes
    return body_bytes

def _vsp_wsgi_wrap_statusv2_fill8(app):
    if getattr(app, "_vsp_wrapped_statusv2_fill8", False):
        return app
    setattr(app, "_vsp_wrapped_statusv2_fill8", True)

    def _wrapped(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/vsp/run_status_v2/"):
            return app(environ, start_response)

        # capture status/headers
        captured = {"status": None, "headers": None, "exc": None}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers) if headers else []
            captured["exc"] = exc_info
            # delay calling real start_response until we potentially rewrite body
            return None

        iterable = app(environ, _sr)

        # buffer body (status_v2 JSON is small)
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
        # Only rewrite when JSON-ish
        hdrs = captured["headers"] or []
        ct = ""
        for k, v in hdrs:
            if str(k).lower() == "content-type":
                ct = str(v).lower()
                break

        if ("application/json" in ct) or (body.lstrip().startswith(b"{")):
            body2 = _vsp_statusv2_fill8_bytes(body)
        else:
            body2 = body

        # fix Content-Length
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
        globals()["application"] = _vsp_wsgi_wrap_statusv2_fill8(_APP)
except Exception:
    pass
# === /VSP_WSGI_STATUSV2_FILL8_MW_V1 ===
'''

p.write_text(t + "\n" + BLOCK + "\n", encoding="utf-8")
print("[OK] appended status_v2 fill8 WSGI middleware")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile wsgi_vsp_ui_gateway.py"
echo "[DONE] installed fill8 middleware (WSGI-level). Restart 8910 to apply."
