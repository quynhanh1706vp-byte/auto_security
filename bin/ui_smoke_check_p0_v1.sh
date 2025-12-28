#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== (1) restart low-mem =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/ui_restart_8910_lowmem_p0_v2.sh

echo "== (2) quick HTTP checks =="
curl -fsS -I http://127.0.0.1:8910/vsp4 | head -n 8
curl -fsS http://127.0.0.1:8910/api/vsp/dashboard_v3 | head -c 200; echo
curl -fsS "http://127.0.0.1:8910/api/vsp/runs_index_v3?limit=40" | head -c 200; echo
curl -fsS "http://127.0.0.1:8910/api/vsp/datasource_v2?limit=200" | head -c 200; echo

echo "== (3) check error log for fresh fatals =="
tail -n 200 out_ci/ui_8910.error.log | egrep -n "SIGKILL|out of memory|Traceback|TimeoutError" || echo "[OK] no fresh fatal"
echo "[OK] UI smoke check passed"
