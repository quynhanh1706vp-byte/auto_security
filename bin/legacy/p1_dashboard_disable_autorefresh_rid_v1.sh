#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && NODE_OK=1 || NODE_OK=0
command -v systemctl >/dev/null 2>&1 && SYS_OK=1 || SYS_OK=0

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P1_DASH_DISABLE_AUTO_REFRESH_RID_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_disable_autorid_${TS}"
echo "[BACKUP] ${JS}.bak_disable_autorid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_DASH_DISABLE_AUTO_REFRESH_RID_V1"

changed = 0

# (A) Disable the scheduled tick starter (setTimeout(tick, 3000);)
pat_timeout = r'^\s*setTimeout\s*\(\s*tick\s*,\s*3000\s*\)\s*;\s*$'
s2, n = re.subn(pat_timeout, f'  /* {mark}: disabled legacy auto-refresh tick start */', s, flags=re.M)
if n:
    s = s2
    changed += n

# (B) Block location.reload() inside the same file (safe: only in dashboard)
pat_reload = r'^\s*location\.reload\s*\(\s*\)\s*;\s*$'
s2, n = re.subn(pat_reload, f'        /* {mark}: blocked legacy location.reload() */', s, flags=re.M)
if n:
    s = s2
    changed += n

# (C) Add marker near the block header if present
if "VSP_P0_DASH_AUTO_REFRESH_RID_V1" in s and mark not in s:
    s = re.sub(r'(\/\*\s*VSP_P0_DASH_AUTO_REFRESH_RID_V1.*\*\/)',
               r'\1\n/* ' + mark + ' */', s, count=1, flags=re.M)
    changed += 1

if changed == 0 and mark in s:
    print("[OK] already patched:", mark)
elif changed == 0:
    print("[WARN] no matching patterns found; file may differ.")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched:", mark, "changed=", changed)
PY

if [ "$NODE_OK" = "1" ]; then
  node --check "$JS" >/dev/null && echo "[OK] node --check ok: $JS" || { echo "[ERR] node --check failed: $JS"; exit 3; }
fi

if [ "$SYS_OK" = "1" ]; then
  systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
fi

echo "[DONE] disabled legacy dashboard auto-refresh RID + blocked reload."
