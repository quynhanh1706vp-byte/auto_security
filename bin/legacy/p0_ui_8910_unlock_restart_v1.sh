#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need bash; need python3; need pgrep; need pkill; need rm; need sleep

LOCK="/tmp/vsp_ui_8910.lock"

echo "== 0) show lock =="
if [ -f "$LOCK" ]; then
  ls -la "$LOCK" || true
  echo "[INFO] lock content:"
  cat "$LOCK" || true
else
  echo "[INFO] no lock file"
fi

echo
echo "== 1) try kill processes that bind 8910 (only gateway UI) =="
# show candidates
pgrep -af "gunicorn.*8910" || true
pgrep -af "wsgi_vsp_ui_gateway" || true

# kill carefully: only gunicorn with 8910 OR gateway module
pkill -TERM -f "gunicorn.*8910" || true
pkill -TERM -f "wsgi_vsp_ui_gateway" || true
sleep 1

# if still alive, hard kill (still only those patterns)
pgrep -af "gunicorn.*8910" >/dev/null 2>&1 && pkill -KILL -f "gunicorn.*8910" || true
pgrep -af "wsgi_vsp_ui_gateway" >/dev/null 2>&1 && pkill -KILL -f "wsgi_vsp_ui_gateway" || true

echo
echo "== 2) remove stale lock =="
if [ -f "$LOCK" ]; then
  rm -f "$LOCK"
  echo "[OK] removed $LOCK"
else
  echo "[OK] no lock to remove"
fi

echo
echo "== 3) gate: py_compile gateway =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo
echo "== 4) start UI =="
if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh
  echo "[OK] start script executed"
else
  echo "[ERR] missing bin/p1_ui_8910_single_owner_start_v2.sh"
  exit 2
fi

echo
echo "== 5) quick smoke (optional) =="
if command -v curl >/dev/null 2>&1; then
  curl -sS -I http://127.0.0.1:8910/ | sed -n '1,12p' || true
  curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,12p' || true
fi

echo "[DONE] unlock + restart attempted."
