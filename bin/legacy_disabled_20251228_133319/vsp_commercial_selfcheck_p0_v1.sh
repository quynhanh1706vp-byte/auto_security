#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== VSP COMMERCIAL SELFCHECK P0 =="

echo "== [1] /vsp4 scripts =="
curl -sS http://127.0.0.1:8910/vsp4 \
| grep -oE 'src="[^"]+static/js/[^"]+"' \
| sed 's/src="//;s/"$//' | nl -ba

echo "== [2] /vsp4 strip headers =="
curl -sSI http://127.0.0.1:8910/vsp4 | grep -i 'content-type\|x-vsp-strip-p\|x-vsp-bundleonly\|cache-control' || true

echo "== [3] latest_rid_v1 =="
curl -sS http://127.0.0.1:8910/api/vsp/latest_rid_v1 | python3 -m json.tool

echo "== [4] health (if exists) =="
curl -sS -I http://127.0.0.1:8910/healthz 2>/dev/null | head -n 5 || true

echo "== [5] recent errors =="
tail -n 80 out_ci/ui_8910.error.log | tail -n 40 || true

echo "== DONE =="
