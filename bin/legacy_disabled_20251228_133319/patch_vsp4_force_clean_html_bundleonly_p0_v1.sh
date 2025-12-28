#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_forceclean_${TS}"
echo "[BACKUP] $APP.bak_forceclean_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_AFTERREQ_FORCE_CLEAN_BUNDLEONLY_P0_V1"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

code = f'''
# --- {MARK}: hard clean /vsp4 HTML + keep ONLY bundle v2 ---
@app.after_request
def vsp_afterreq_force_clean_bundleonly_p0_v1(resp):
    try:
        from flask import request
        path = getattr(request, "path", "") or ""
        if path != "/vsp4":
            return resp

        ctype = (getattr(resp, "mimetype", "") or "").lower()
        if "html" not in ctype or getattr(resp, "status_code", 200) != 200:
            return resp

        body = resp.get_data(as_text=True)

        # (0) Drop any garbage BEFORE <!DOCTYPE or <html
        idx = body.lower().find("<!doctype")
        if idx == -1:
            idx = body.lower().find("<html")
        if idx > 0:
            body = body[idx:]

        # (1) Find asset_v from existing bundle tag, else fallback
        m = re.search(r'vsp_bundle_commercial_v2\\.js\\?v=(\\d+)', body, re.I)
        asset_v = m.group(1) if m else "1"

        # (2) Remove ALL external script tags that reference /static/js/P* OR /static/js/vsp_* (we will re-add bundle)
        def drop_external_scripts(html: str) -> str:
            parts = html.split("<script")
            if len(parts) == 1:
                return html
            out = [parts[0]]
            for chunk in parts[1:]:
                seg = "<script" + chunk
                low = seg.lower()
                # inline script => keep
                if 'src="' not in low and "src='" not in low:
                    out.append(seg); continue
                # detect src value quickly
                if "/static/js/p" in low or "static/js/p" in low:
                    end = low.find("</script>")
                    if end != -1:
                        continue
                if "/static/js/vsp_" in low or "static/js/vsp_" in low:
                    end = low.find("</script>")
                    if end != -1:
                        continue
                out.append(seg)
            return "".join(out)

        body2 = drop_external_scripts(body)

        # (3) Ensure exactly one bundle v2 tag before </body>
        bundle_tag = f'<script defer src="/static/js/vsp_bundle_commercial_v2.js?v={{asset_v}}"></script>'
        # remove any existing bundle tags first
        body2 = re.sub(r'(?is)\\s*<script\\b[^>]*vsp_bundle_commercial_v2\\.js[^>]*>\\s*</script\\s*>\\s*', "\\n", body2)

        if re.search(r"(?is)</body\\s*>", body2):
            body2 = re.sub(r"(?is)</body\\s*>", "\\n"+bundle_tag+"\\n</body>", body2, count=1)
        else:
            body2 += "\\n" + bundle_tag + "\\n"

        resp.set_data(body2)
        resp.headers["Cache-Control"] = "no-store"
        resp.headers["X-VSP-BUNDLEONLY"] = "FORCE_CLEAN_P0_V1"
    except Exception:
        pass
    return resp
'''

m2 = re.search(r'(?m)^if\\s+__name__\\s*==\\s*[\'"]__main__[\'"]\\s*:', s)
ins = m2.start() if m2 else len(s)
s2 = s[:ins] + "\n" + code + "\n" + s[ins:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected", MARK)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
