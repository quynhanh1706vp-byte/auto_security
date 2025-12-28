#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="templates/vsp_4tabs_commercial_v1.html"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_force_ids_${TS}"
echo "[BACKUP] $T.bak_force_ids_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("templates/vsp_4tabs_commercial_v1.html")
s=p.read_text(encoding="utf-8", errors="ignore")

def ensure_block(pid, tab):
    global s
    if f'id="{pid}"' in s:
        return
    # inject near end of body for safety
    ins = s.rfind("</body>")
    if ins < 0:
        ins = len(s)
    block = f'\n<div id="{pid}" data-tab-content="{tab}" style="display:none"></div>\n'
    s = s[:ins] + block + s[ins:]

# normalize known variants
s = s.replace('id="vsp4-dashboard-main"', 'id="vsp-dashboard-main"')
s = s.replace('id="vsp-dashboard-root"', 'id="vsp-dashboard-main"')

# ensure required ids exist
if 'id="vsp-dashboard-main"' not in s:
    # try to locate a dashboard pane and tag it
    s = re.sub(r'(<div[^>]+data-vsp-main="dashboard"[^>]*)(>)', r'\1 id="vsp-dashboard-main"\2', s, count=1)
if 'id="vsp-dashboard-main"' not in s:
    ensure_block("vsp-dashboard-main", "dashboard")

ensure_block("vsp-pane-runs", "runs")
ensure_block("vsp-pane-settings", "settings")
ensure_block("vsp-pane-datasource", "datasource")

p.write_text(s, encoding="utf-8")
print("[OK] ensured router pane ids exist")
PY

echo "[OK] patched $T"
