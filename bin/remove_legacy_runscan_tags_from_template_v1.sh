#!/usr/bin/env bash
set -euo pipefail
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] not found: $TPL"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$TPL.bak_rm_runscan_${TS}"
echo "[BACKUP] $TPL.bak_rm_runscan_${TS}"

python3 - << 'PY'
from pathlib import Path
import re
tpl = Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

# Remove (or comment) exact tags
def kill(src):
    global txt
    pat = rf'(?m)^\s*<script[^>]+src="/static/js/{re.escape(src)}"[^>]*>\s*</script>\s*$'
    txt2 = re.sub(pat, f'<!-- VSP_COMMERCIAL: removed {src} -->', txt)
    return txt2

for src in [
    "vsp_runs_trigger_scan_ui_v3.js",
    "vsp_runs_trigger_scan_mount_hook_v1.js",
]:
    txt = kill(src)

tpl.write_text(txt, encoding="utf-8")
print("[OK] removed legacy runscan script tags from template")
PY

pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "=== verify tags ==="
curl -s http://localhost:8910/ | grep -n "vsp_runs_commercial_panel_v1.js" | head
curl -s http://localhost:8910/ | grep -n "vsp_runs_trigger_scan_ui_v3.js" | head || true
