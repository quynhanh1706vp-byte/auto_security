#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need date
command -v systemctl >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

# pick latest backup made by forcecss patch
BK="$(ls -1t ${WSGI}.bak_forcecss_* 2>/dev/null | head -n 1 || true)"
[ -n "${BK:-}" ] || { echo "[ERR] no backup found: ${WSGI}.bak_forcecss_*"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.broken_${TS}" 2>/dev/null || true
cp -f "$BK" "$WSGI"
echo "[OK] restored $WSGI from $BK (saved broken as ${WSGI}.broken_${TS})"

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
else
  echo "[WARN] $SVC not active; restart manually if needed"
fi
