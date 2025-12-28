#!/usr/bin/env bash
set -euo pipefail
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PORT=8910
BASE="http://127.0.0.1:${PORT}"

echo "== [1] unit summary =="
sudo systemctl status "$SVC" -n 30 --no-pager || true
echo
echo "== [2] show ExecStart/Env =="
sudo systemctl show "$SVC" -p FragmentPath -p DropInPaths -p Environment -p ExecStart -p MainPID -p NRestarts --no-pager | sed 's/; /\n  /g'
echo
echo "== [3] listener on :$PORT =="
ss -lptn "sport = :${PORT}" || true
echo
echo "== [4] journal last 120 lines (important) =="
sudo journalctl -u "$SVC" -n 120 --no-pager | tail -n 120
echo
echo "== [5] retry rid_latest (20x) =="
for i in $(seq 1 20); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/rid_latest" >/tmp/rid.json 2>/dev/null; then
    echo "[OK] up try=$i"; cat /tmp/rid.json; echo
    exit 0
  fi
  sleep 0.2
done
echo "[FAIL] still not reachable: $BASE"
exit 2
