#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "$APP.bak_fix_bundleonly_${TS}"
echo "[BACKUP] $APP.bak_fix_bundleonly_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# remove the broken block (v1) if present
s = re.sub(r'(?s)\n# --- VSP_AFTERREQ_BUNDLE_ONLY_VSP4_P0_V1:.*?\n(?=# ---|@app\.|def |if __name__|$)', "\n", s)

MARK = "VSP_AFTERREQ_BUNDLE_ONLY_VSP4_P0_V2"
if MARK in s:
    print("[OK] already patched v2 (skip)")
    p.write_text(s, encoding="utf-8")
    raise SystemExit(0)

code = """
# --- VSP_AFTERREQ_BUNDLE_ONLY_VSP4_P0_V2: force /vsp4 to load ONLY bundle v2 (commercial) ---
@app.after_request
def vsp_afterreq_bundle_only_vsp4_p0_v2(resp):
    try:
        from flask import request
        import re as _re
        path = getattr(request, "path", "") or ""
        if not (path == "/vsp4" or path.startswith("/vsp4/")):
            return resp
        ctype = (getattr(resp, "mimetype", "") or "").lower()
        if "html" not in ctype:
            return resp
        if getattr(resp, "status_code", 200) != 200:
            return resp

        body = resp.get_data(as_text=True)

        # pick asset_v from any existing vsp_* tag
        m = _re.search(r'src="[^"]*/static/js/vsp_[^"]+\\?v=(\\d+)"', body, _re.I)
        asset_v = m.group(1) if m else "1"

        # drop all <script ... src=".../static/js/vsp_*.js..."></script> tags (simple, robust)
        # NOTE: we only target tags that contain '/static/js/vsp_' to avoid touching libs.
        def drop_vsp_scripts(html: str) -> str:
            parts = html.split("<script")
            if len(parts) == 1:
                return html
            out = [parts[0]]
            for chunk in parts[1:]:
                seg = "<script" + chunk
                # keep non-src scripts
                if 'src="' not in seg and "src='" not in seg:
                    out.append(seg); continue
                # keep only if not a vsp js
                if "/static/js/vsp_" not in seg and "static/js/vsp_" not in seg:
                    out.append(seg); continue
                # remove the whole script tag (best-effort)
                end = seg.lower().find("</script>")
                if end == -1:
                    continue
                # drop it
            return "".join(out)

        body2 = drop_vsp_scripts(body)

        # insert exactly one bundle tag before </body>
        bundle_tag = f'<script defer src="/static/js/vsp_bundle_commercial_v2.js?v={asset_v}"></script>'
        if _re.search(r"(?is)</body\\s*>", body2):
            body2 = _re.sub(r"(?is)</body\\s*>", "\\n"+bundle_tag+"\\n</body>", body2, count=1)
        else:
            body2 += "\\n" + bundle_tag + "\\n"

        resp.set_data(body2)
        resp.headers["Cache-Control"] = "no-store"
    except Exception:
        pass
    return resp
"""

# inject before __main__ guard or at EOF
m = re.search(r'(?m)^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
ins = m.start() if m else len(s)
s2 = s[:ins] + "\n" + code + "\n" + s[ins:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected bundle-only v2 for /vsp4")
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
