#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
TPL="templates/vsp_5tabs_enterprise_v2.html"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
B1="$F.bak_enterprise_tpl_${TS}"
cp -f "$F" "$B1"
echo "[BACKUP] $B1"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_SWITCH_ENTERPRISE_TEMPLATE_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Replace common template choices used by /vsp4 handler
cands = [
  "vsp_4tabs_commercial_v1.html",
  "vsp_dashboard_2025.html",
  "vsp_5tabs_enterprise_v1.html",
]
target = "vsp_5tabs_enterprise_v2.html"

hit = False
for old in cands:
    if old in s:
        s = s.replace(old, target)
        hit = True

# If no string match, try a conservative regex: render_template("...vsp...html")
if not hit:
    s2 = re.sub(r'render_template\(\s*[\'"]([^\'"]*vsp[^\'"]*\.html)[\'"]',
                lambda m: f'render_template("{target}"',
                s, count=1)
    if s2 != s:
        s = s2
        hit = True

if not hit:
    print("[WARN] cannot find any known template string in vsp_demo_app.py; no change made.")
    raise SystemExit(0)

s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== restart 8910 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh

echo "== smoke =="
if ! bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_5tabs_smoke_p2_v1.sh; then
  echo "[FAIL] smoke failed -> ROLLBACK"
  cp -f "$B1" "$F"
  python3 -m py_compile vsp_demo_app.py || true
  bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh || true
  exit 3
fi

echo "== stability 120 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_stability_strict_lock_p0_v2.sh 120

echo "[DONE] /vsp4 is now enterprise template. Ctrl+Shift+R http://127.0.0.1:8910/vsp4"
