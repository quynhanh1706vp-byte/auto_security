#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "$APP.bak_vsp4_bundleonly_${TS}"
echo "[BACKUP] $APP.bak_vsp4_bundleonly_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_AFTERREQ_BUNDLE_ONLY_VSP4_P0_V1"
if MARK in s:
    print("[OK] already patched (skip)")
    raise SystemExit(0)

code = rf'''
# --- {MARK}: force /vsp4 to load ONLY bundle v2 (commercial) ---
@app.after_request
def vsp_afterreq_bundle_only_vsp4_p0_v1(resp):
    try:
        from flask import request
        path = getattr(request, "path", "") or ""
        if not (path == "/vsp4" or path.startswith("/vsp4/")):
            return resp
        ctype = (getattr(resp, "mimetype", "") or "").lower()
        if "html" not in ctype:
            return resp
        if getattr(resp, "status_code", 200) != 200:
            return resp

        body = resp.get_data(as_text=True)

        # grab existing cache-bust v=... from any vsp_* script tag if present
        m = re.search(r'src="[^"]*/static/js/vsp_[^"]+\\?v=(\\d+)"', body, re.I)
        asset_v = m.group(1) if m else None
        if not asset_v:
            # fallback: keep stable-ish
            asset_v = "1"

        # remove ALL vsp_* script tags except the bundle v2
        def keep_or_drop(match):
            src = (match.group(1) or "").strip()
            if "vsp_bundle_commercial_v2.js" in src:
                return ""  # we will re-insert exactly once
            if "/static/js/vsp_" in src or "static/js/vsp_" in src:
                return "\n"
            return match.group(0)

        script_re = re.compile(r'(?is)\\s*<script\\b[^>]*\\bsrc\\s*=\\s*["\\']([^"\\']+)["\\'][^>]*>\\s*</script\\s*>\\s*')
        body2 = script_re.sub(keep_or_drop, body)

        # insert exactly one bundle tag before </body>
        bundle_tag = f'<script defer src="/static/js/vsp_bundle_commercial_v2.js?v={{asset_v}}"></script>'
        if re.search(r'(?is)</body\\s*>', body2):
            body2 = re.sub(r'(?is)</body\\s*>', "\\n"+bundle_tag+"\\n</body>", body2, count=1)
        else:
            body2 += "\\n" + bundle_tag + "\\n"

        resp.set_data(body2)
        resp.headers["Cache-Control"] = "no-store"
    except Exception:
        pass
    return resp
'''

# inject before __main__ guard or at EOF
m = re.search(r'(?m)^if\\s+__name__\\s*==\\s*[\'"]__main__[\'"]\\s*:', s)
ins = m.start() if m else len(s)
s2 = s[:ins] + "\n" + code + "\n" + s[ins:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected after_request bundle-only for /vsp4")
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
