#!/usr/bin/env bash
set -u
cd /home/test/Data/SECURITY_BUNDLE/ui || exit 2

echo "== (A) stop systemd service =="
sudo systemctl stop vsp-ui-8910.service 2>/dev/null || true

echo "== (B) kill any stray gunicorn 8910 =="
pkill -f 'gunicorn .*127\.0\.0\.1:8910' 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.6

echo "== (C) start via systemd =="
sudo systemctl start vsp-ui-8910.service || true
sleep 0.8

echo "== (D) status quick =="
sudo systemctl --no-pager -l status vsp-ui-8910.service || true

echo "== (E) ss listen =="
ss -ltnp | grep ':8910' || true

echo "== (F) curl retry (10 tries) =="
ok=0
for i in $(seq 1 10); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 1 http://127.0.0.1:8910/vsp5 2>/dev/null || echo FAIL)"
  echo "try#$i http_code=$code"
  if [ "$code" != "FAIL" ] && [ "$code" != "000" ]; then ok=1; break; fi
  sleep 0.4
done

echo "== (G) if still failing: show logs =="
echo "-- boot.log tail --"
tail -n 120 out_ci/ui_8910.boot.log 2>/dev/null || true
echo "-- error.log tail --"
tail -n 160 out_ci/ui_8910.error.log 2>/dev/null || true

echo "== (H) journalctl last 120 lines =="
sudo journalctl -u vsp-ui-8910.service --no-pager -n 120 2>/dev/null || true

echo "== (I) kernel OOM hints (last 60) =="
dmesg -T 2>/dev/null | tail -n 60 | egrep -i "killed process|oom|out of memory" || true

if [ "$ok" = "1" ]; then
  echo "[OK] 8910 reachable now."
  curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 240; echo
else
  echo "[FAIL] 8910 still unstable/refused. Use the logs above to pinpoint crash reason."
fi
