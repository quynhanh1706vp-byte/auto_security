#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
A="vsp_demo_app.py"

pick(){ ls -1t "$1".bak_* 2>/dev/null | head -n 1 || true; }

BW="$(pick "$W")"
BA="$(pick "$A")"

[ -n "${BW:-}" ] || { echo "[ERR] no backup for $W"; exit 2; }
[ -n "${BA:-}" ] || { echo "[ERR] no backup for $A"; exit 2; }

echo "[RESTORE]"
echo " - $W <= $BW"
echo " - $A <= $BA"

cp -f "$BW" "$W"
cp -f "$BA" "$A"

python3 -m py_compile "$W" "$A"
echo "[OK] py_compile ok"

# Restart best-effort (NO password prompt)
if command -v systemctl >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1; then
    sudo -n systemctl restart "$SVC" >/dev/null 2>&1 || true
  else
    systemctl restart "$SVC" >/dev/null 2>&1 || true
  fi
  systemctl is-active "$SVC" 2>/dev/null || true
fi

echo "[DONE] rollback done."
