#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_stripP_${TS}"
echo "[BACKUP] $APP.bak_stripP_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_AFTERREQ_STRIP_PSCRIPT_P0_V1"
if MARK in s:
    print("[OK] already patched (skip)")
    raise SystemExit(0)

code = f'''
# --- {MARK}: /vsp4 keep ONLY vsp_bundle_commercial_v2.js and drop /static/js/P* script ---
@app.after_request
def vsp_afterreq_strip_pscript_p0_v1(resp):
    try:
        from flask import request
        path = getattr(request, "path", "") or ""
        if not (path == "/vsp4" or path.startswith("/vsp4/")):
            return resp
        ctype = (getattr(resp, "mimetype", "") or "").lower()
        if "html" not in ctype or getattr(resp, "status_code", 200) != 200:
            return resp

        body = resp.get_data(as_text=True)

        # Remove any <script ... src="/static/js/P....">...</script>
        # (very conservative: only matches '/static/js/P' prefix)
        body2 = re.sub(r'(?is)\\s*<script\\b[^>]*\\bsrc\\s*=\\s*["\\\'](/static/js/P[^"\\\']+)["\\\'][^>]*>\\s*</script\\s*>\\s*', "\\n", body)

        # Also remove any other vsp_*.js tags except the bundle v2
        def keep_only_bundle(m):
            src = (m.group(1) or "")
            if "vsp_bundle_commercial_v2.js" in src:
                return m.group(0)
            if "/static/js/vsp_" in src or "static/js/vsp_" in src:
                return "\\n"
            return m.group(0)

        body2 = re.sub(r'(?is)<script\\b[^>]*\\bsrc\\s*=\\s*["\\\']([^"\\\']+)["\\\'][^>]*>\\s*</script\\s*>', keep_only_bundle, body2)

        # Ensure bundle tag exists (if someone removed it)
        if "vsp_bundle_commercial_v2.js" not in body2:
            # try keep the same v= from old body if present
            mv = re.search(r'vsp_bundle_commercial_v2\\.js\\?v=(\\d+)', body, re.I)
            vv = mv.group(1) if mv else "1"
            bundle_tag = f'<script defer src="/static/js/vsp_bundle_commercial_v2.js?v={{vv}}"></script>'
            if re.search(r"(?is)</body\\s*>", body2):
                body2 = re.sub(r"(?is)</body\\s*>", "\\n"+bundle_tag+"\\n</body>", body2, count=1)
            else:
                body2 += "\\n" + bundle_tag + "\\n"

        resp.set_data(body2)
        resp.headers["Cache-Control"] = "no-store"
        resp.headers["X-VSP-BUNDLEONLY"] = "STRIP_PSCRIPT_P0_V1"
    except Exception:
        pass
    return resp
'''

m = re.search(r'(?m)^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
ins = m.start() if m else len(s)
s2 = s[:ins] + "\n" + code + "\n" + s[ins:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected", MARK)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
