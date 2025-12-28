#!/usr/bin/env bash
set -euo pipefail
TPL="templates/vsp_dashboard_2025.html"
BK="$TPL.bak_runscan_mount_hook_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BK"
echo "[BACKUP] $BK"

python3 - << 'PY'
from pathlib import Path
import re
tpl = Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8", errors="ignore")

hook = '<script src="/static/js/vsp_runs_trigger_scan_mount_hook_v1.js" defer></script>\n'

if "vsp_runs_trigger_scan_mount_hook_v1.js" in txt:
    print("[SKIP] hook tag already present")
else:
    # insert right after v3 tag if possible
    txt2, n = re.subn(
        r'(<script\s+src="/static/js/vsp_runs_trigger_scan_ui_v3\.js"\s+defer></script>\s*)',
        r'\1' + hook,
        txt,
        count=1,
        flags=re.IGNORECASE
    )
    if n == 0:
        txt2, n2 = re.subn(r'(?i)</head>', hook + '</head>', txt, count=1)
        txt = txt2 if n2 else (txt + "\n" + hook)
    else:
        txt = txt2

    tpl.write_text(txt, encoding="utf-8")
    print("[OK] injected hook tag")
PY

echo "=== VERIFY TAGS ==="
grep -n "vsp_runs_trigger_scan_ui_v3.js" -n "$TPL" | head
grep -n "vsp_runs_trigger_scan_mount_hook_v1.js" -n "$TPL" | head
