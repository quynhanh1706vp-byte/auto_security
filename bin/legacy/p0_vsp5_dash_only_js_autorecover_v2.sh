#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need date; need ls
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"

echo "== [0] check current =="
if node --check "$JS" >/dev/null 2>&1; then
  echo "[OK] current JS compiles. No recover needed."
  exit 0
fi

echo "== [1] snapshot broken =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_broken_${TS}"
echo "[BACKUP] ${JS}.bak_broken_${TS}"

echo "== [2] find latest compiling backup (scan all baks) =="
GOOD=""
for f in $(ls -1t ${JS}.bak_* 2>/dev/null || true); do
  if node --check "$f" >/dev/null 2>&1; then
    GOOD="$f"
    break
  fi
done

[ -n "$GOOD" ] || { echo "[FATAL] No compiling backup found."; exit 2; }

echo "[OK] restoring from: $GOOD"
cp -f "$GOOD" "$JS"
node --check "$JS"

echo "== [3] restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Restored JS. Hard refresh /vsp5."
