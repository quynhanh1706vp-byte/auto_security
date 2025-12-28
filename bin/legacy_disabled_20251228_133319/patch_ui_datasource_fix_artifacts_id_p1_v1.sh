#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_art_id_${TS}" && echo "[BACKUP] $F.bak_art_id_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_datasource_tab_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# Replace any RUN_ prefix concatenation for artifacts calls
s2 = re.sub(r'RUN_\s*\+\s*rid', 'rid', s)
s2 = re.sub(r'`RUN_\$\{rid\}`', '`'+'${rid}'+'`', s2)
s2 = re.sub(r'"RUN_"\s*\+\s*rid', 'rid', s2)

p.write_text(s2, encoding="utf-8")
print("[OK] removed RUN_ prefix in artifacts id usage (best-effort)")
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] Hard refresh Ctrl+Shift+R"
