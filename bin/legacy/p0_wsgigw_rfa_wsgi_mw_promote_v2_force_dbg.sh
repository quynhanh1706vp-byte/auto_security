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
cp -f "$W" "${W}.bak_rfa_wsgimw_v2_${TS}"
echo "[BACKUP] ${W}.bak_rfa_wsgimw_v2_${TS}"

python3 - "$W" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

TAG="VSP_P0_WSGIGW_RFA_WSGI_MW_PROMOTE_V2_FORCE_DBG"
if TAG in s:
    print("[OK] already patched"); raise SystemExit(0)

addon = f"""

# --- {TAG} ---
def __vsp_promote_findings_contract_v2(j):
    \"\"\"If findings is missing/empty but items exists -> promote items -> findings.\"\"\"
    try:
        if not isinstance(j, dict):
            return j, 0, 0, 0, 0
        before = j.get("findings")
        items = j.get("items")
        b = len(before) if isinstance(before, list) else 0
        it = len(items) if isinstance(items, list) else 0

        # Only promote when findings is empty AND items has data
        if b == 0 and it > 0:
            j["findings"] = items
        after = j.get("findings")
        a = len(after) if isinstance(after, list) else 0
        changed = 1 if (a != b) else 0
        return j, b, it, a, changed
    except Exception:
        return j, 0, 0, 0, 0

class __VspRfaPromoteWSGIMW_V2:
    \"\"\"Outer-most WSGI promoter for /api/vsp/run_file_allow (force rewrite + debug).\"\"\"
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

        # header helpers
        def _set_header(k, v):
            nonlocal headers
            headers = [(hk, hv) for (hk, hv) in headers if hk.lower() != k.lower()]
            headers.append((k, v))

        # Always signal promote MW
        _set_header("X-VSP-RFA-PROMOTE", "v2")

        # Determine if we can rewrite JSON
        try:
            code = int(str(status).split()[0])
        except Exception:
            code = 200

        hmap = {{}}
        for hk, hv in headers:
            hmap.setdefault(hk.lower(), hv)

        ct = (hmap.get("content-type") or "").lower()
        ce = (hmap.get("content-encoding") or "").lower()

        body = b"".join(chunks)

        # If not JSON/200 or encoded, just pass-through (with header)
        if code != 200 or "application/json" not in ct or (ce and ce not in ("identity", "")):
            _set_header("X-VSP-RFA-PROMOTE-DBG", f"skip code={code} ct={ct[:32]} ce={ce[:16]}")
            start_response(status, headers, exc_info)
            return [body]

        if not body.strip():
            _set_header("X-VSP-RFA-PROMOTE-DBG", "empty-body")
            start_response(status, headers, exc_info)
            return [body]

        # Parse/promote/rewrite when needed
        try:
            import json
            j = json.loads(body.decode("utf-8", "replace"))
            j, b, it, a, changed = __vsp_promote_findings_contract_v2(j)
            _set_header("X-VSP-RFA-PROMOTE-DBG", f"b={b};it={it};a={a};chg={changed}")

            # rewrite ONLY when promotion happened (a > b)
            if a > b:
                out = json.dumps(j, ensure_ascii=False).encode("utf-8")
                headers = [(hk, hv) for (hk, hv) in headers if hk.lower() not in ("content-length", "transfer-encoding")]
                headers.append(("Content-Length", str(len(out))))
                start_response(status, headers, exc_info)
                return [out]
        except Exception as e:
            _set_header("X-VSP-RFA-PROMOTE-DBG", f"jsonerr:{type(e).__name__}")
            start_response(status, headers, exc_info)
            return [body]

        # no change
        start_response(status, headers, exc_info)
        return [body]

# wrap again to become outer-most
try:
    application = __VspRfaPromoteWSGIMW_V2(application)
except Exception:
    try:
        app = __VspRfaPromoteWSGIMW_V2(app)
    except Exception:
        pass
# --- /{TAG} ---

"""

s = s.rstrip() + "\n" + addon
p.write_text(s, encoding="utf-8")
print("[OK] appended V2 outer-most WSGI MW (force+dbg)")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
