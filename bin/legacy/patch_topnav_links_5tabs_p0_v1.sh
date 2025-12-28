#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TPL="templates/vsp_dashboard_2025.html"
MARK="VSP_TOPNAV_LINKS_5TABS_P0_V1"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_${MARK}_${TS}"
echo "[BACKUP] $TPL.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

tpl=Path("templates/vsp_dashboard_2025.html")
s=tpl.read_text(encoding="utf-8", errors="replace")

# helper: replace href target by visible label (robust-ish)
def repl(label, href):
    global s
    # <a ...>LABEL</a>
    pat = rf'(<a\b[^>]*\bhref=")[^"]*("([^>]*?)>\s*{re.escape(label)}\s*</a>)'
    s2, n = re.subn(pat, rf'\1{href}\2', s, flags=re.I)
    return n, s2

total=0
for label, href in [
    ("Dashboard", "/vsp4"),
    ("Runs & Reports", "/runs"),
    ("Data Source", "/data"),
    ("Settings", "/settings"),
    ("Rule Overrides", "/rule_overrides"),
]:
    n, s_new = repl(label, href)
    if n:
        s = s_new
        total += n

# fallback: old ids if your nav uses data-tab keys
s = re.sub(r'href="/vsp4#runs"', 'href="/runs"', s)
s = re.sub(r'href="/vsp4#data"', 'href="/data"', s)

tpl.write_text(s, encoding="utf-8")
print("[OK] patched topnav links. changes=", total)
PY

echo "[NEXT] hard refresh Ctrl+Shift+R then click tabs."
