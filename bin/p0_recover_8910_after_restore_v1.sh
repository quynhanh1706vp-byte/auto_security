#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need ss; need curl; need python3; need sed; need grep; need awk

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"

echo "== precheck: py_compile wsgi =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

echo "== status before =="
systemctl status "$SVC" --no-pager -l || true

echo "== who listens :8910 (before) =="
ss -ltnp 2>/dev/null | grep -E ':(8910)\s' || true

echo "== cleanup stale locks if any =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true

echo "== kill anyone holding :8910 =="
PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910[[:space:]]/ {print $0}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// }" ]; then
  echo "[INFO] killing PIDS: $PIDS"
  kill -9 $PIDS 2>/dev/null || true
fi

echo "== restart systemd =="
systemctl restart "$SVC" || true
sleep 1

echo "== status after restart =="
systemctl status "$SVC" --no-pager -l || true

echo "== listeners :8910 (after) =="
if ss -ltnp 2>/dev/null | grep -qE ':(8910)\s'; then
  ss -ltnp 2>/dev/null | grep -E ':(8910)\s' || true
else
  echo "[WARN] no listener on 8910 after systemd restart"
fi

echo "== smoke curl /vsp5 =="
if curl -fsS "$BASE/vsp5" >/dev/null 2>&1; then
  echo "[OK] /vsp5 reachable via systemd"
  curl -fsS "$BASE/vsp5" | head -n 5
  exit 0
fi

echo "== systemd failed; show journal tail =="
journalctl -u "$SVC" -n 120 --no-pager || true

echo "== fallback: run gunicorn manually (best effort) =="
# try to detect exported var: "app = application" or "application = ..."
APPVAR="$(python3 - <<'PY'
import re
s=open("wsgi_vsp_ui_gateway.py","r",encoding="utf-8",errors="replace").read()
# prefer explicit app=
m=re.search(r'^\s*app\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*$', s, re.M)
if m:
    print("app")
    raise SystemExit
# else common gunicorn entry "application"
print("application")
PY
)"
echo "[INFO] gunicorn entry var=$APPVAR"

# stop systemd to avoid fighting
systemctl stop "$SVC" 2>/dev/null || true

# run in background
LOG="/tmp/vsp_ui_8910_fallback.log"
rm -f "$LOG" 2>/dev/null || true
nohup gunicorn -w 2 -b 127.0.0.1:8910 "wsgi_vsp_ui_gateway:${APPVAR}" >"$LOG" 2>&1 &

sleep 1
echo "== listeners :8910 (fallback) =="
ss -ltnp 2>/dev/null | grep -E ':(8910)\s' || true

echo "== smoke curl /vsp5 (fallback) =="
curl -fsS "$BASE/vsp5" | head -n 8
echo "[OK] fallback gunicorn up. log=$LOG"
