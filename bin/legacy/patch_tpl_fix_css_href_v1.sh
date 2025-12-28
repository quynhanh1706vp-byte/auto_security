#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="templates/vsp_4tabs_commercial_v1.html"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_csshref_${TS}"
echo "[BACKUP] $T.bak_csshref_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("templates/vsp_4tabs_commercial_v1.html")
s=p.read_text(encoding="utf-8", errors="replace")

# Fix: href="...css" ?v="123"  ==> href="...css?v=123"
pat = re.compile(r'(href="[^"]+\.css")\s*\?v="([^"]+)"')
new = pat.sub(lambda m: f'href="{m.group(1)[6:-1]}?v={m.group(2)}"', s)

if new == s:
    print("[WARN] pattern not found (skip)"); 
else:
    p.write_text(new, encoding="utf-8")
    print("[OK] fixed css href ?v= in template")
PY
