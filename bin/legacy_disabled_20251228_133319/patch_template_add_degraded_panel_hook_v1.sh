#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_degraded_hook_${TS}"
echo "[BACKUP] $TPL.bak_degraded_hook_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8", errors="ignore")

tag = '<script src="/static/js/vsp_degraded_panel_hook_v1.js" defer></script>'
if "vsp_degraded_panel_hook_v1.js" in txt:
    print("[OK] already present")
    raise SystemExit(0)

# Insert near end of </body> if present, else append
m = re.search(r"</body\s*>", txt, flags=re.I)
if m:
    out = txt[:m.start()] + "\n  " + tag + "\n" + txt[m.start():]
else:
    out = txt + "\n" + tag + "\n"

tpl.write_text(out, encoding="utf-8")
print("[OK] injected script tag into template")
PY
