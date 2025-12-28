#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== headers /runs =="
curl -sS -D- http://127.0.0.1:8910/runs -o /tmp/vsp_runs_body.html | sed -n '1,40p'
echo
echo "== tail error log (NEW only) =="
tail -n 260 out_ci/ui_8910.error.log | sed -n '1,260p'
echo
echo "== grep likely exceptions =="
grep -nE "Traceback|ERROR|Exception|KeyError|FileNotFoundError|JSONDecodeError|PermissionError|sqlite|No such file|500" out_ci/ui_8910.error.log | tail -n 80 || true

echo
echo "== show first 80 lines of /runs body (fallback HTML often contains why) =="
sed -n '1,80p' /tmp/vsp_runs_body.html || true
