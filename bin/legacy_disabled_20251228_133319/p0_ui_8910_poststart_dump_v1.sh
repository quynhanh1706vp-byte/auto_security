#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${BASE:-http://127.0.0.1:8910}"

echo "== start =="
rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh || true
sleep 1.2

echo
echo "== ss :8910 =="
ss -ltnp | grep 8910 || true

echo
echo "== ps gateway gunicorn =="
ps aux | egrep 'wsgi_vsp_ui_gateway|gunicorn.*8910' | grep -v egrep || true

echo
echo "== curl / =="
curl -sS -I "$BASE/" | sed -n '1,15p' || true

echo
echo "== tail boot/error/access =="
tail -n 200 out_ci/ui_8910.boot.log 2>/dev/null || true
echo "---"
tail -n 200 out_ci/ui_8910.error.log 2>/dev/null || true
echo "---"
tail -n 60 out_ci/ui_8910.access.log 2>/dev/null || true

echo
echo "== tail nohup.out =="
tail -n 200 nohup.out 2>/dev/null || true
