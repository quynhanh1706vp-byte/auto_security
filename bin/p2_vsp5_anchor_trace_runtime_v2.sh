#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need sed; need ss; need ps

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_VSP5_ANCHOR_TRACE_V2_${TS}"

echo "== [0] who serves :8910 right now? =="
ss -ltnp | grep -E ':(8910)\b' || true
ps -ef | egrep 'gunicorn|vsp_demo_app|wsgi_vsp_ui_gateway|vsp-ui' | grep -v egrep || true

echo "== [1] patch source file (add marker + anchor) =="
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_trace_${TS}"
echo "[BACKUP] ${F}.bak_trace_${TS}"

python3 - <<PY
from pathlib import Path
import sys

p = Path("$F")
s = p.read_text(errors="ignore")

needle = '<div id="vsp5_root"></div>'
if needle not in s:
    print("[ERR] cannot find '<div id=\"vsp5_root\"></div>' in", p)
    sys.exit(2)

# inject marker comment + anchor before vsp5_root
inject = f'<!-- { "$MARK" } -->\\n  <div id="vsp-dashboard-main"></div>\\n\\n  <div id="vsp5_root"></div>'
s2 = s.replace(needle, inject, 1)

p.write_text(s2)
print("[OK] patched source with marker:", "$MARK")
PY

echo "== [2] restart service (NO silencing errors) =="
if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] systemctl restart $SVC"
  systemctl restart "$SVC"
  systemctl --no-pager --full status "$SVC" | sed -n '1,35p' || true
else
  echo "[WARN] systemctl not found; cannot restart service here"
fi

echo "== [3] verify live /vsp5 contains marker + anchor =="
HTML="$(curl -fsS "$BASE/vsp5")"
echo "$HTML" | grep -n "$MARK" | head -n 2 || echo "[ERR] marker NOT found in live HTML"
echo "$HTML" | grep -n 'id="vsp-dashboard-main"' | head -n 2 || echo "[ERR] anchor NOT found in live HTML"

echo "== [4] show first lines of live html (for quick eyeball) =="
echo "$HTML" | sed -n '1,80p'

echo "[DONE] If marker is missing -> runtime is NOT using $F, or restart didn't hit the right service."
