#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TPL="templates/vsp_4tabs_commercial_v1.html"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 3; }

cp -f "$APP" "$APP.bak_rmP_pyfix_${TS}"
cp -f "$TPL" "$TPL.bak_rmP_${TS}"
echo "[BACKUP] $APP.bak_rmP_pyfix_${TS}"
echo "[BACKUP] $TPL.bak_rmP_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

# (A) Fix vsp_demo_app.py: remove literal '\n' lines that break python (line continuation + 'n')
p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
lines = s.splitlines(True)
new = []
rm = 0
for ln in lines:
    if re.match(r'^\s*\\n\s*$', ln):
        rm += 1
        continue
    new.append(ln)
if rm:
    p.write_text("".join(new), encoding="utf-8")
print("[OK] vsp_demo_app.py removed literal \\\\n lines:", rm)

# (B) Fix template: remove any <script ... src="/static/js/P....">...</script> (including broken quote ?v= outside)
t = Path("templates/vsp_4tabs_commercial_v1.html")
h = t.read_text(encoding="utf-8", errors="replace")
h2, n = re.subn(r'(?is)\n?\s*<script\b[^>]*\bsrc="/static/js/P[^"]*"[^>]*>\s*</script\s*>\s*\n?', "\n", h)
if n:
    t.write_text(h2, encoding="utf-8")
print("[OK] template removed P* script tags:", n)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"

echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
