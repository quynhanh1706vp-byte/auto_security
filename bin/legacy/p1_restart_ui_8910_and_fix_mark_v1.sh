#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need awk; need sed; need ss; need curl; need date

# 1) Fix MARK unbound in the previous script (best-effort)
S="/home/test/Data/SECURITY_BUNDLE/ui/bin/p1_patch_vsp_commercial_all3_p1_v1.sh"
if [ -f "$S" ]; then
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$S" "${S}.bak_fix_mark_${TS}"
  # insert MARK variable near top if not already present
  if ! grep -q '^MARK=' "$S"; then
    awk '
      NR==1{print; next}
      NR==2{print "MARK=\"VSP_P1_POLISH_ALL3_V1\""; print; next}
      {print}
    ' "$S" > "${S}.tmp.$$"
    mv -f "${S}.tmp.$$" "$S"
    chmod +x "$S"
    echo "[OK] fixed MARK unbound in $S (backup: ${S}.bak_fix_mark_${TS})"
  else
    echo "[OK] $S already has MARK"
  fi
else
  echo "[WARN] not found: $S (skip fix MARK)"
fi

# 2) Restart UI on 8910 (no systemd service on your host)
echo "== find PID listen :8910 =="
PID="$(ss -ltnp 2>/dev/null | awk '/:8910[[:space:]]/ && /users:\(\(" /{print}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1 || true)"
if [ -n "${PID:-}" ]; then
  echo "[INFO] killing PID=$PID (listen :8910)"
  kill "$PID" 2>/dev/null || true
  sleep 0.6
  kill -9 "$PID" 2>/dev/null || true
else
  echo "[INFO] no PID found for :8910 (maybe not running)"
fi

# clear lock to avoid "another start in progress"
rm -f /tmp/vsp_ui_8910.lock || true

echo "== start UI =="
if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh || true
else
  echo "[ERR] missing bin/p1_ui_8910_single_owner_start_v2.sh"
  echo "[HINT] please start UI with your usual command"
fi

sleep 1.0
echo "== ss :8910 =="
ss -ltnp | egrep '(:8910)\b' || true

echo "== smoke curl =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,12p' || true
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,12p' || true

echo
echo "== verify patch marker in bundle =="
grep -n "VSP_P1_POLISH_ALL3_V1" static/js/vsp_bundle_commercial_v2.js | head -n 3 || true

echo
echo "DONE. Now Ctrl+F5 /vsp5 to see changes."
