#!/usr/bin/env bash
set -euo pipefail
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_degraded_v3_${TS}"
echo "[BACKUP] $TPL.bak_degraded_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
tpl = Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8", errors="ignore")

# remove older v2/v1 tags if present
for s in ["vsp_degraded_panel_hook_v1.js","vsp_degraded_panel_hook_v2.js","vsp_degraded_panel_hook_v3.js"]:
    txt = txt.replace(f'<script src="/static/js/{s}" defer></script>', '')

tag = '\n<script src="/static/js/vsp_degraded_panel_hook_v3.js" defer></script>\n'
if "</body>" in txt:
    txt = txt.replace("</body>", tag + "</body>")
elif "</head>" in txt:
    txt = txt.replace("</head>", tag + "</head>")
else:
    txt += tag

tpl.write_text(txt, encoding="utf-8")
print("[OK] injected v3 hook")
PY
