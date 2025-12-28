#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "$APP.bak_bundleonly_p0_v4_${TS}"
echo "[BACKUP] $APP.bak_bundleonly_p0_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Remove any previous broken bundle-only functions (all variants)
s = re.sub(r'(?s)\n@app\.after_request\s*\ndef\s+vsp_afterreq_bundle_only_vsp4[^\n]*\n.*?\n\s*return\s+resp\s*\n', "\n", s)

# 2) Remove the exact problematic regex assignment lines anywhere (they break py parser)
lines = s.splitlines(True)
out = []
rm = 0
for ln in lines:
    if re.search(r'\bscript_re\s*=\s*re\.compile\(', ln):
        rm += 1
        continue
    out.append(ln)
s = "".join(out)

# 3) Inject clean bundle-only after_request (NO tricky quoting)
MARK = "VSP_AFTERREQ_BUNDLE_ONLY_VSP4_P0_V4"
if MARK not in s:
    code = f"""
# --- {MARK}: force /vsp4 to load ONLY bundle v2 (commercial) ---
@app.after_request
def vsp_afterreq_bundle_only_vsp4_p0_v4(resp):
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

        # try reuse existing ?v=... if present
        m = _re.search(r'/static/js/vsp_[^"\\']+\\?v=(\\d+)', body, _re.I)
        asset_v = m.group(1) if m else "1"

        # remove ALL vsp_*.js script tags (except bundle v2 which we reinject once)
        pat = _re.compile(r\"\"\"(?is)<script\\b[^>]*\\bsrc\\s*=\\s*(['"])([^'"]*?/static/js/vsp_[^'"]+)\\1[^>]*>\\s*</script\\s*>\"\"\")
        def repl(mm):
            src = (mm.group(2) or "")
            if "vsp_bundle_commercial_v2.js" in src:
                return "\\n"  # drop, we'll insert exactly once
            return "\\n"
        body2 = pat.sub(repl, body)

        bundle_tag = f'<script defer src="/static/js/vsp_bundle_commercial_v2.js?v={{asset_v}}"></script>'
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
    # insert before __main__ guard if exists, else append
    m2 = re.search(r'(?m)^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
    ins = m2.start() if m2 else len(s)
    s = s[:ins] + "\n" + code + "\n" + s[ins:]

p.write_text(s, encoding="utf-8")
print(f"[OK] removed script_re lines={rm} + injected {MARK}")
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
