#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_loader_route_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_tabeq_${TS}" && echo "[BACKUP] $F.bak_tabeq_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_ui_loader_route_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_ROUTE_TAB_EQ_V1" in s:
    print("[OK] already patched")
else:
    # find inside normRoute() after the split/trim line
    pat = r"(h\s*=\s*h\.split\('\?'\)\[0\]\.split\('&'\)\[0\]\.trim\(\)\s*;)"
    m = re.search(pat, s)
    if not m:
        raise SystemExit("[ERR] cannot find normRoute split line to patch")
    inject = m.group(1) + r"""
    // VSP_ROUTE_TAB_EQ_V1: accept hashes like "#tab=datasource&sev=HIGH"
    if (h.startsWith('tab=')) {
      h = h.slice(4).trim();
    } else if (h.includes('tab=')) {
      const mm = h.match(/(?:^|&)tab=([^&]+)/);
      if (mm && mm[1]) h = String(mm[1]).trim();
    }
"""
    s = s.replace(m.group(1), inject, 1)
    p.write_text(s, encoding="utf-8")
    print("[OK] patched loader to support #tab=...")

PY

node --check "$F" >/dev/null && echo "[OK] node --check OK"

echo "== restart 8910 (NO restore) =="
bash bin/ui_restart_8910_no_restore_v1.sh

echo "[NEXT] Ctrl+Shift+R, then open: #tab=datasource OR #datasource"
