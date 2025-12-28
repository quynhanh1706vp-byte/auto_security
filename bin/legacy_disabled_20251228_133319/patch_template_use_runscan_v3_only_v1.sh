#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
BK="$TPL.bak_runscan_v3_only_$(date +%Y%m%d_%H%M%S)"

cp "$TPL" "$BK"
echo "[BACKUP] $BK"

python3 - << 'PY'
from pathlib import Path
import re

tpl = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8", errors="ignore")

# remove older runscan-related scripts to avoid double-init
patterns = [
  r'<script[^>]+src="/static/js/vsp_runs_scan_panel_ui_v1\.js"[^>]*>\s*</script>\s*',
  r'<script[^>]+src="/static/js/vsp_runs_scan_panel_hook_v1\.js"[^>]*>\s*</script>\s*',
  r'<script[^>]+src="/static/js/vsp_runs_trigger_scan_v1\.js"[^>]*>\s*</script>\s*',
  r'<script[^>]+src="/static/js/vsp_runs_trigger_scan_ui_v2\.js"[^>]*>\s*</script>\s*',
]
for p in patterns:
  txt = re.sub(p, "", txt, flags=re.IGNORECASE)

tag = '<script src="/static/js/vsp_runs_trigger_scan_ui_v3.js" defer></script>\n'
if "vsp_runs_trigger_scan_ui_v3.js" not in txt:
  txt2, n = re.subn(r'(?i)</head>', tag + '</head>', txt, count=1)
  txt = txt2 if n else (txt + "\n" + tag)

tpl.write_text(txt, encoding="utf-8")
print("[OK] template now uses runscan v3 only")
PY

echo "=== VERIFY ==="
grep -n "vsp_runs_.*scan" -n "$TPL" | head -n 50
