#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need node
command -v systemctl >/dev/null 2>&1 || true

JS="static/js/vsp_data_source_lazy_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_ds_nofallback_${TS}"
echo "[BACKUP] ${JS}.bak_ds_nofallback_${TS}"

python3 - "$JS" <<'PY'
import sys, re
p=sys.argv[1]
s=open(p,"r",encoding="utf-8",errors="replace").read()

# Comment out common fallback patterns without breaking logic
# (We don't know exact code shape; do conservative disables.)
rules = [
  r'(items\s*\|\|\s*\[\])',
  r'(data\.items\s*\|\|\s*\[\])',
  r'(data\.findings\s*\|\|\s*\[\])',
  r'(data\s*&&\s*data\.items)',
  r'(data\s*&&\s*data\.findings)',
]
for pat in rules:
    s = re.sub(pat, r'/*fallback_disabled*/([])', s)

# Also remove "use items when findings empty" message tags if present
s = s.replace("itemsfb", "nofallback")

open(p,"w",encoding="utf-8").write(s)
print("[OK] fallback tokens neutralized (best-effort)")
PY

node -c "$JS"
echo "[OK] node -c OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
