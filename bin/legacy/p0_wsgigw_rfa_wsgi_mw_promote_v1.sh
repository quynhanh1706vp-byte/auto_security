#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rfa_wsgimw_${TS}"
echo "[BACKUP] ${W}.bak_rfa_wsgimw_${TS}"

python3 - "$W" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

TAG="VSP_P0_WSGIGW_RFA_WSGI_MW_PROMOTE_V1"
if TAG in s:
    print("[OK] already patched"); raise SystemExit(0)

addon = f"""

# --- {TAG} ---
def __vsp_promote_findings_contract(j):
    try:
        if not isinstance(j, dict):
            return j
        f = j.get("findings")
        if isinstance(f, list) and f:
            return j

        cands = []
        it = j.get("items")
        if isinstance(it, list) and it:
            cands = it

        dt = j.get("data")
        if not cands and isinstance(dt, list) and dt:
            cands = dt

        if not cands and isinstance(dt, dict):
            for k in ("findings","items","data"):
                v = dt.get(k)
                if isinstance(v, list) and v:
                    cands = v
                    break

        j["findings"] = cands if isinstance(cands, list) else []
    except Exception:
        pass
    return j

class __VspRfaPromoteWSGIMW:
    \"""
    WSGI-level promoter for /api/vsp/run_file_allow:
    - Adds header: X-VSP-RFA-PROMOTE: v2
    - If JSON and findings empty but items present -> copy items -> findings
    \"""
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO") or ""
        if path != "/api/vsp/run_file_allow":
            return self.app(environ, start_response)

        status_box = {{}}
        chunks = []

        def _write(b):
            if b:
                chunks.append(b)

        def _start_response(status, headers, exc_info=None):
            status_box["status"] = status
            status_box["headers"] = list(headers or [])
            status_box["exc_info"] = exc_info
            return _write

        app_iter = self.app(environ, _start_response)
        try:
            for x in app_iter:
                if x:
                    chunks.append(x)
        finally:
            try:
                if hasattr(app_iter, "close"):
                    app_iter.close()
            except Exception:
                pass

        status = status_box.get("status") or "200 OK"
        headers = status_box.get("headers") or []
        exc_info = status_box.get("exc_info")

        # always add promote header (commercial signal)
        def _set_header(k, v):
            nonlocal headers
            headers = [(hk, hv) for (hk, hv) in headers if hk.lower() != k.lower()]
            headers.append((k, v))

        _set_header("X-VSP-RFA-PROMOTE", "v2")

        # only rewrite if 200 + JSON + not encoded
        try:
            code = int(str(status).split()[0])
        except Exception:
            code = 200

        hmap = {{}}
        for hk, hv in headers:
            hmap.setdefault(hk.lower(), hv)

        ct = (hmap.get("content-type") or "").lower()
        ce = (hmap.get("content-encoding") or "").lower()
        if code != 200 or "application/json" not in ct or (ce and ce not in ("identity", "")):
            start_response(status, headers, exc_info)
            return [b"".join(chunks)]

        body = b"".join(chunks)
        # empty -> pass through with header
        if not body.strip():
            start_response(status, headers, exc_info)
            return [body]

        # parse+promote+rewrite
        try:
            import json
            j = json.loads(body.decode("utf-8", "replace"))
            before = j.get("findings")
            j = __vsp_promote_findings_contract(j)
            after = j.get("findings")

            if before != after:
                out = json.dumps(j, ensure_ascii=False).encode("utf-8")
                # fix Content-Length
                headers = [(hk, hv) for (hk, hv) in headers if hk.lower() not in ("content-length", "transfer-encoding")]
                headers.append(("Content-Length", str(len(out))))
                start_response(status, headers, exc_info)
                return [out]
        except Exception:
            pass

        # no change -> pass-through (but with header)
        start_response(status, headers, exc_info)
        return [body]

# wrap the exported application (gunicorn entrypoint)
try:
    application = __VspRfaPromoteWSGIMW(application)
except Exception:
    try:
        app = __VspRfaPromoteWSGIMW(app)
    except Exception:
        pass
# --- /{TAG} ---

"""

s = s.rstrip() + "\\n" + addon
p.write_text(s, encoding="utf-8")
print("[OK] appended WSGI MW promoter and wrapped application")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
