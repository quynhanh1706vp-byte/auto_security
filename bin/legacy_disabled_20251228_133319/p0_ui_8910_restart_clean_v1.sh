#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need rm; need sleep; need pkill; need pgrep; need python3; need curl

LOCK="/tmp/vsp_ui_8910.lock"

echo "== stop old gunicorn on 8910 =="
pgrep -af "gunicorn.*8910" || true
pkill -TERM -f "gunicorn.*8910" || true
sleep 1
pgrep -af "gunicorn.*8910" >/dev/null 2>&1 && pkill -KILL -f "gunicorn.*8910" || true

echo "== remove stale lock =="
rm -f "$LOCK" || true

echo "== gate: py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo "== start =="
bin/p1_ui_8910_single_owner_start_v2.sh

echo "== smoke =="
sleep 1
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,12p'
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,12p'
echo "[DONE]"
