#!/usr/bin/env bash
set -euo pipefail
TPL="templates/vsp_dashboard_2025.html"
BK="$TPL.bak_runscan_commercial_v1_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BK"
echo "[BACKUP] $BK"

python3 - << 'PY'
from pathlib import Path
import re
tpl = Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8", errors="ignore")

# Add CSS link (if not present)
css_tag = '<link rel="stylesheet" href="/static/css/vsp_runscan_commercial_v1.css">\n'
if "vsp_runscan_commercial_v1.css" not in txt:
    txt, n = re.subn(r'(?i)</head>', css_tag + '</head>', txt, count=1)
    if n: print("[OK] added CSS link")

# Add JS tag (defer) near other runs scripts
js_tag = '<script src="/static/js/vsp_runs_scan_panel_commercial_v1.js" defer></script>\n'
if "vsp_runs_scan_panel_commercial_v1.js" not in txt:
    # insert after v3 tag if exists
    txt2, n = re.subn(r'(<script\s+src="/static/js/vsp_runs_trigger_scan_ui_v3\.js"\s+defer></script>\s*)',
                      r'\1' + js_tag, txt, count=1, flags=re.IGNORECASE)
    if n == 0:
        txt2, n2 = re.subn(r'(?i)</head>', js_tag + '</head>', txt, count=1)
        txt = txt2 if n2 else (txt + "\n" + js_tag)
        print("[OK] injected commercial JS near </head>")
    else:
        txt = txt2
        print("[OK] injected commercial JS after v3")

tpl.write_text(txt, encoding="utf-8")
print("[DONE] template updated")
PY

echo "=== VERIFY ==="
grep -n "vsp_runscan_commercial_v1.css" -n "$TPL" | head || true
grep -n "vsp_runs_scan_panel_commercial_v1.js" -n "$TPL" | head || true
