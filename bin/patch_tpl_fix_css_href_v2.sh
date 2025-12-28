#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="templates/vsp_4tabs_commercial_v1.html"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_csshref2_${TS}"
echo "[BACKUP] $T.bak_csshref2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("templates/vsp_4tabs_commercial_v1.html")
s=p.read_text(encoding="utf-8", errors="replace")

# Fix: href="/.../x.css"?v=20251215_090230  ==> href="/.../x.css?v=20251215_090230"
pat = re.compile(r'href="([^"]+\.css)"\?v=([0-9A-Za-z_]+)')
new = pat.sub(r'href="\1?v=\2"', s)

if new == s:
    print("[WARN] css href ?v= pattern not found (skip)")
else:
    p.write_text(new, encoding="utf-8")
    print("[OK] fixed css href ?v= -> in-href querystring")
PY

/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_wait_v1.sh
