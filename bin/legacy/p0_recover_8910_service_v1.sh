#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [A] status =="
sudo systemctl status vsp-ui-8910.service --no-pager || true

echo
echo "== [B] kill anything on :8910 (if any) =="
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*:8910 .*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// }" ]; then
  echo "[KILL] $PIDS"
  sudo kill -9 $PIDS || true
else
  echo "[OK] no listener on :8910"
fi

echo
echo "== [C] remove lock (if used) =="
sudo rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true

echo
echo "== [D] restart service =="
sudo systemctl restart vsp-ui-8910.service

echo
echo "== [E] wait & verify =="
for i in 1 2 3 4 5; do
  if curl -fsS --max-time 2 "$BASE/" >/dev/null 2>&1; then
    echo "[OK] HTTP 200 /"
    break
  fi
  echo "[WAIT] $i"
  sleep 0.6
done

echo
echo "== [F] ss :8910 =="
ss -ltnp | egrep '(:8910)' || true

echo
echo "== [G] quick API check =="
curl -sS --max-time 3 "$BASE/api/vsp/runs?limit=2" | head -c 300; echo
