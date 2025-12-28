#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== baseline =="
echo "time=$(date -Is)"
echo -n "NRestarts="; systemctl show -p NRestarts --value vsp-ui-8910.service || true
echo -n "MainPID="; systemctl show -p MainPID --value vsp-ui-8910.service || true
echo

echo "== wait until FAIL (max 120s) =="
for i in $(seq 1 480); do
  ts="$(date +%T.%3N)"
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 1 \
    http://127.0.0.1:8910/api/vsp/runs?limit=1 2>/dev/null || echo FAIL)"
  echo "$ts code=$code"
  if [ "$code" = "FAIL" ] || [ "$code" = "000" ]; then
    echo
    echo "===== HIT FAIL at $ts ====="
    echo "== ss :8910 =="
    ss -ltnp | grep ':8910' || echo "[NO LISTENER]"
    echo
    echo "== systemctl status =="
    sudo systemctl --no-pager -l status vsp-ui-8910.service | sed -n '1,140p' || true
    echo
    echo "== journalctl last 200 =="
    sudo journalctl -u vsp-ui-8910.service --no-pager -n 200 || true
    echo
    echo "== error.log tail 200 =="
    tail -n 200 out_ci/ui_8910.error.log 2>/dev/null || true
    echo
    echo "== boot.log tail 120 =="
    tail -n 120 out_ci/ui_8910.boot.log 2>/dev/null || true
    echo
    echo "== ps gunicorn =="
    ps -ef | egrep "gunicorn|wsgi_vsp_ui_gateway" | grep -v egrep || true
    exit 0
  fi
  sleep 0.25
done

echo "[OK] no FAIL observed in 120s"
