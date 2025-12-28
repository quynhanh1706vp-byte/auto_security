#!/usr/bin/env bash
set -euo pipefail
SVC="vsp-ui-8910.service"
BASE="http://127.0.0.1:8910"

echo "== (1) systemd status =="
sudo systemctl status "$SVC" --no-pager -l || true
echo

echo "== (2) last journal (200 lines) =="
sudo journalctl -u "$SVC" -n 200 --no-pager || true
echo

echo "== (3) try start =="
sudo systemctl reset-failed "$SVC" || true
sudo systemctl start "$SVC" || true
sleep 1.0
echo

echo "== (4) listen check =="
ss -lntp | grep -E '127\.0\.0\.1:8910' || echo "[ERR] still not listening"
echo

echo "== (5) curl quick check =="
curl -sS -I "$BASE/vsp5" | head -n 12 || true
echo

echo "== (6) if still down, show unit + boot logs =="
sudo systemctl cat "$SVC" --no-pager || true
echo
cd /home/test/Data/SECURITY_BUNDLE/ui || exit 0
for f in out_ci/ui_8910.boot.log out_ci/ui_8910.error.log out_ci/ui_8910.access.log; do
  [ -f "$f" ] && { echo "---- $f (tail 120) ----"; tail -n 120 "$f"; echo; } || true
done
