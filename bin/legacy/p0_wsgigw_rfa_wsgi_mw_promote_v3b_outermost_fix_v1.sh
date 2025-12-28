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
cp -f "$W" "${W}.bak_rfa_wsgimw_v3b_${TS}"
echo "[BACKUP] ${W}.bak_rfa_wsgimw_v3b_${TS}"

python3 - "$W" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

TAG="VSP_P0_WSGIGW_RFA_WSGI_MW_PROMOTE_V3B_OUTERMOST_FIX_V1"
if TAG in s:
    print("[OK] already patched"); raise SystemExit(0)

addon_tmpl = r'''
# --- __TAG__ ---
try:
    import json as _vsp_json
except Exception:
    _vsp_json = None

class __VspRfaPromoteWSGIMW_V3B:
    """
    Outermost WSGI promoter for /api/vsp/run_file_allow:
      - Header: X-VSP-RFA-PROMOTE: v3
      - Debug:  X-VSP-RFA-PROMOTE-DBG / X-VSP-RFA-PROMOTE-ERR
      - Rule: if findings is empty and items is non-empty -> findings = items
      - Rewrites JSON when promotion happens
    """
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO") or ""
        if path != "/api/vsp/run_file_allow":
            return self.app(environ, start_response)

        status_box = {}
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
        body = b"".join(chunks)

        def _set_header(k, v):
            nonlocal headers
            headers = [(hk, hv) for (hk, hv) in headers if hk.lower() != k.lower()]
            headers.append((k, v))

        _set_header("X-VSP-RFA-PROMOTE", "v3")

        # quick gate: only JSON 200 and no encoding
        try:
            code_i = int(str(status).split()[0])
        except Exception:
            code_i = 200

        hmap = {}
        for hk, hv in headers:
            hmap.setdefault(hk.lower(), hv)

        ct = (hmap.get("content-type") or "").lower()
        ce = (hmap.get("content-encoding") or "").lower()

        if code_i != 200 or "application/json" not in ct or (ce and ce not in ("identity", "")) or _vsp_json is None:
            _set_header("X-VSP-RFA-PROMOTE-DBG", "skip code=%s ct=%s ce=%s" % (code_i, ct[:32], ce[:16]))
            start_response(status, headers, exc_info)
            return [body]

        if not body.strip():
            _set_header("X-VSP-RFA-PROMOTE-DBG", "empty-body")
            start_response(status, headers, exc_info)
            return [body]

        try:
            j = _vsp_json.loads(body.decode("utf-8", "replace"))
            f = j.get("findings")
            it = j.get("items")
            b = len(f) if isinstance(f, list) else 0
            n = len(it) if isinstance(it, list) else 0
            changed = 0

            if b == 0 and n > 0:
                j["findings"] = it
                changed = 1

            a = len(j.get("findings")) if isinstance(j.get("findings"), list) else 0
            _set_header("X-VSP-RFA-PROMOTE-DBG", "b=%d;it=%d;a=%d;chg=%d" % (b, n, a, changed))

            if changed:
                out = _vsp_json.dumps(j, ensure_ascii=False).encode("utf-8")
                headers = [(hk, hv) for (hk, hv) in headers if hk.lower() not in ("content-length", "transfer-encoding")]
                headers.append(("Content-Length", str(len(out))))
                start_response(status, headers, exc_info)
                return [out]

        except Exception as e:
            msg = str(e).replace("\n", " ")[:160]
            _set_header("X-VSP-RFA-PROMOTE-ERR", "%s:%s" % (type(e).__name__, msg))
            start_response(status, headers, exc_info)
            return [body]

        start_response(status, headers, exc_info)
        return [body]

# Wrap as OUTERMOST
try:
    application = __VspRfaPromoteWSGIMW_V3B(application)
except Exception:
    try:
        app = __VspRfaPromoteWSGIMW_V3B(app)
    except Exception:
        pass
# --- /__TAG__ ---
'''

addon = addon_tmpl.replace("__TAG__", TAG)

s = s.rstrip() + "\n" + addon
p.write_text(s, encoding="utf-8")
print("[OK] appended V3B outermost MW (force promote + dbg/err)")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
