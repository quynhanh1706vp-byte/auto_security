#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need head; need tail; need date

echo "== [A] find backups =="
mapfile -t BAKS < <(ls -1 ${W}.bak_* 2>/dev/null | sort -r)
[ "${#BAKS[@]}" -gt 0 ] || { echo "[ERR] no backups found"; exit 2; }
echo "found ${#BAKS[@]} backups"
printf '%s\n' "${BAKS[@]}" | head -n 12

echo "== [B] pick first backup that py_compile passes =="
picked=""
for b in "${BAKS[@]}"; do
  cp -f "$b" "$W"
  if python3 -m py_compile "$W" >/dev/null 2>&1; then
    picked="$b"
    echo "[OK] picked: $picked"
    break
  else
    echo "[SKIP] bad: $b"
  fi
done
[ -n "$picked" ] || { echo "[ERR] no compilable backup found"; exit 2; }

echo "== [C] restart service =="
sudo systemctl restart vsp-ui-8910.service || true
sudo systemctl status vsp-ui-8910.service --no-pager -l | sed -n '1,25p'

echo "== [D] verify port and a simple GET =="
ss -ltnp | grep ':8910' || echo "NO_LISTENER_8910"
BASE="http://127.0.0.1:8910"
curl -fsS -D /tmp/_h -o /tmp/_b "$BASE/api/vsp/runs?limit=1" || true
echo "-- head --"; sed -n '1,10p' /tmp/_h
echo "-- body --"; head -c 160 /tmp/_b; echo
