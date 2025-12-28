#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_fix_stripP_${TS}"
echo "[BACKUP] $APP.bak_fix_stripP_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# (1) remove literal '\n' lines that break python
lines = s.splitlines(True)
new = []
rm = 0
for ln in lines:
    if re.match(r'^\s*\\n\s*$', ln):
        rm += 1
        continue
    new.append(ln)
s = "".join(new)

# (2) remove previous failed injection (marker)
s = re.sub(r'(?s)\n# --- VSP_AFTERREQ_STRIP_PSCRIPT_RESPONSE_P0_V1:.*?\n(?=(\n# ---|\n@app\.|\ndef |\nclass |\nif __name__|$))', "\n", s)

MARK = "VSP_AFTERREQ_STRIP_PSCRIPT_RESPONSE_P0_V2"
if MARK not in s:
    code = (
        "\n# --- " + MARK + ": force-strip /static/js/P* script tags from /vsp4 HTML (handles broken quote ?v= outside) ---\n"
        "@app.after_request\n"
        "def vsp_afterreq_strip_pscript_response_p0_v2(resp):\n"
        "    try:\n"
        "        from flask import request\n"
        "        path = getattr(request, \"path\", \"\") or \"\"\n"
        "        if path != \"/vsp4\":\n"
        "            return resp\n"
        "        ctype = (getattr(resp, \"mimetype\", \"\") or \"\").lower()\n"
        "        if \"html\" not in ctype or getattr(resp, \"status_code\", 200) != 200:\n"
        "            return resp\n"
        "        body = resp.get_data(as_text=True)\n"
        "        # remove <script ... src=\"/static/js/Pxxxx\"?v=...></script>\n"
        "        body2 = re.sub(r'(?is)\\s*<script\\b[^>]*\\bsrc=\"/static/js/P[^\"]*\"(?:\\?v=[^>]*)?[^>]*>\\s*</script\\s*>\\s*', \"\\n\", body)\n"
        "        resp.set_data(body2)\n"
        "        resp.headers[\"Cache-Control\"] = \"no-store\"\n"
        "        resp.headers[\"X-VSP-STRIP-P\"] = \"P0_V2\"\n"
        "    except Exception:\n"
        "        pass\n"
        "    return resp\n"
    )
    m2 = re.search(r'(?m)^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
    ins = m2.start() if m2 else len(s)
    s = s[:ins] + code + s[ins:]

p.write_text(s, encoding="utf-8")
print("[OK] removed_literal_backslash_n_lines=", rm)
print("[OK] injected", MARK)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910 (hardreset) + Ctrl+Shift+R"
