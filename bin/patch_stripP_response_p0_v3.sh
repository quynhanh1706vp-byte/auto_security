#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_stripP_v3_${TS}"
echo "[BACKUP] $APP.bak_stripP_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_AFTERREQ_STRIP_PSCRIPT_RESPONSE_P0_V3"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

code = f"""
# --- {MARK}: strip /static/js/P* script tags from /vsp4 HTML (robust + header) ---
@app.after_request
def vsp_afterreq_strip_pscript_response_p0_v3(resp):
    try:
        from flask import request
        import re as _re

        path = getattr(request, "path", "") or ""
        if path != "/vsp4":
            return resp
        ctype = (getattr(resp, "mimetype", "") or "").lower()
        if "html" not in ctype or getattr(resp, "status_code", 200) != 200:
            return resp

        # set probe header early (even if stripping fails)
        resp.headers["X-VSP-STRIP-P"] = "P0_V3"
        resp.headers["Cache-Control"] = "no-store"

        body = resp.get_data(as_text=True)

        # 1) remove normal P-script tags
        body2 = _re.sub(r'(?is)\\s*<script\\b[^>]*\\bsrc="/static/js/P[^"]*"[^>]*>\\s*</script\\s*>\\s*', "\\n", body)

        # 2) remove broken quote form: src="/static/js/Pxxx"?v=....
        body2 = _re.sub(r'(?is)\\s*<script\\b[^>]*\\bsrc="/static/js/P[^"]*"\\?v=[^>]*>\\s*</script\\s*>\\s*', "\\n", body2)

        resp.set_data(body2)
    except Exception:
        pass
    return resp
"""

m2 = re.search(r'(?m)^if\\s+__name__\\s*==\\s*[\'"]__main__[\'"]\\s*:', s)
ins = m2.start() if m2 else len(s)
s2 = s[:ins] + "\n" + code + "\n" + s[ins:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected", MARK)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
