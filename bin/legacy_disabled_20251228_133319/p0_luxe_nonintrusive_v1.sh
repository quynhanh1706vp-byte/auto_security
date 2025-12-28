#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_nonintr_${TS}"
echo "[BACKUP] ${JS}.bak_nonintr_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Disable any automatic hideLegacyByDefault(root) call
s2, n = re.subn(r'^\s*hideLegacyByDefault\(\s*root\s*\);\s*$',
                r'      // [NONINTR] legacy stays visible by default\n      // hideLegacyByDefault(root);\n',
                s, flags=re.M)

# 2) Ensure toggle button (if exists) flips legacy display (already in your file) - no further action.
p.write_text(s2, encoding="utf-8")
print("[OK] disabled auto-hide legacy calls:", n)
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] luxe is now non-intrusive (legacy stays visible)"
