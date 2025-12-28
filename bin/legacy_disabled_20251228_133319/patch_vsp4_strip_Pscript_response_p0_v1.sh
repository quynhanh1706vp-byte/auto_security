#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_stripP_resp_${TS}"
echo "[BACKUP] $APP.bak_stripP_resp_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_AFTERREQ_STRIP_PSCRIPT_RESPONSE_P0_V1"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

code = f'''
# --- {MARK}: force-strip /static/js/P* script tags from /vsp4 HTML (handles broken quote ?v= outside) ---
@app.after_request
def vsp_afterreq_strip_pscript_response_p0_v1(resp):
    try:
        from flask import request
        path = getattr(request, "path", "") or ""
        if path != "/vsp4":
            return resp
        ctype = (getattr(resp, "mimetype", "") or "").lower()
        if "html" not in ctype or getattr(resp, "status_code", 200) != 200:
            return resp

        body = resp.get_data(as_text=True)

        # Remove script tag where src points to /static/js/P... even if the query is outside the quote:
        #   <script ... src="/static/js/Pxxxx"?v=YYYY ...></script>
        body2 = re.sub(r'(?is)\\s*<script\\b[^>]*\\bsrc="/static/js/P[^"]*"(?:\\?v=[^>]*)?[^>]*>\\s*</script\\s*>\\s*', "\\n", body)

        resp.set_data(body2)
        resp.headers["Cache-Control"] = "no-store"
        resp.headers["X-VSP-STRIP-P"] = "P0_V1"
    except Exception:
        pass
    return resp
'''

m2 = re.search(r'(?m)^if\\s+__name__\\s*==\\s*[\'"]__main__[\'"]\\s*:', s)
ins = m2.start() if m2 else len(s)
s2 = s[:ins] + "\\n" + code + "\\n" + s[ins:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected", MARK)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
