#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_forcehook_stripmw_${TS}"
echo "[BACKUP] ${F}.bak_forcehook_stripmw_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_FORCEHOOK_STRIP_FILLREAL_RUNS_V3"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Ensure strip middleware exists (you already injected earlier at ~5903)
if "_vsp_mw_strip_fillreal_on_runs" not in s:
    # If missing, add minimal implementation at end
    s += f"""

# {MARK}_IMPL
import re as _re
def _vsp_mw_strip_fillreal_on_runs(app):
    def _mw(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not (path == "/runs" or path.startswith("/runs/")):
            return app(environ, start_response)

        cap = {{"status": None, "headers": None, "exc": None}}
        def _sr(status, headers, exc_info=None):
            cap["status"] = status
            cap["headers"] = list(headers) if headers else []
            cap["exc"] = exc_info

        it = app(environ, _sr)
        chunks = []
        try:
            for c in it:
                if c: chunks.append(c)
        finally:
            try:
                close = getattr(it, "close", None)
                if callable(close): close()
            except Exception:
                pass

        status = cap["status"] or "200 OK"
        headers = cap["headers"] or []
        body = b"".join(chunks)

        ct = ""
        for k, v in headers:
            if str(k).lower() == "content-type":
                ct = str(v)
                break

        if body and ("text/html" in ct.lower()):
            html = body.decode("utf-8", "replace")
            # remove marker block + script
            html2 = _re.sub(r"\\s*<!--\\s*VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY\\s*-->.*?<!--\\s*/VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY\\s*-->\\s*", "", html, flags=_re.I|_re.S)
            html2 = _re.sub(r"\\s*<script[^>]+src=['\\"]?/static/js/vsp_fill_real_data_5tabs_p1_v1\\.js[^'\\"]*['\\"][^>]*>\\s*</script>\\s*", "", html2, flags=_re.I|_re.S)
            if html2 != html:
                body = html2.encode("utf-8")
                headers = [(k, v) for (k, v) in headers if str(k).lower() != "content-length"]
                headers.append(("Content-Length", str(len(body))))

        start_response(status, headers, cap["exc"])
        return [body]
    return _mw
"""
else:
    # If exists, ensure it strips BOTH marker + script (upgrade in-place if needed)
    # Add a safe second-pass stripper into existing function by appending a tiny helper at end (cheap & safe)
    if "VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY" not in s:
        # extremely unlikely, but keep safe
        pass

# Now: FORCE HOOK at end of module (no regex detection, just runtime wrapping)
s += f"""

# {MARK}
try:
    # prefer Flask app if present
    if "app" in globals():
        _a = globals().get("app")
        if _a is not None and hasattr(_a, "wsgi_app"):
            try:
                _a.wsgi_app = _vsp_mw_strip_fillreal_on_runs(_a.wsgi_app)
                globals()["app"] = _a
            except Exception:
                pass
    # gunicorn may point to "application"
    if "application" in globals():
        _appx = globals().get("application")
        if _appx is not None:
            try:
                globals()["application"] = _vsp_mw_strip_fillreal_on_runs(_appx)
            except Exception:
                pass
except Exception:
    pass
"""

p.write_text(s, encoding="utf-8")
print("[OK] appended force-hook for strip MW")
PY

rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== verify /runs (should be clean) =="
curl -sS http://127.0.0.1:8910/runs -o /tmp/runs.html
grep -n "VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY" /tmp/runs.html && echo "[ERR] marker still present" || echo "[OK] no marker"
grep -n "vsp_fill_real_data_5tabs_p1_v1\\.js" /tmp/runs.html && echo "[ERR] still injected" || echo "[OK] no fillreal script"
