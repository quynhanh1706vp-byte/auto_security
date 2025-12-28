#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PORT=8910
BIND="127.0.0.1:${PORT}"
OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci"
PIDFILE="${OUT}/ui_${PORT}.pid"
BASE="http://127.0.0.1:${PORT}"
MOD="wsgi_vsp_ui_gateway"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
need sudo
need systemctl
need ss
command -v journalctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v systemd-analyze >/dev/null 2>&1 || true

echo "== [0] detect callable (application/app) =="
CALLABLE="$(python3 - <<'PY'
import importlib
m=importlib.import_module("wsgi_vsp_ui_gateway")
print("application" if hasattr(m,"application") else ("app" if hasattr(m,"app") else "application"))
PY
)"
echo "[OK] callable=${MOD}:${CALLABLE}"

echo "== [1] gunicorn path (venv preferred) =="
GUNI="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn"
if [ ! -x "$GUNI" ]; then GUNI="$(command -v gunicorn || true)"; fi
[ -n "${GUNI:-}" ] || { echo "[ERR] gunicorn not found"; exit 2; }
echo "[OK] gunicorn=$GUNI"

echo "== [2] write FINAL drop-in (must override all others) =="
DROP="/etc/systemd/system/${SVC}.d"
sudo mkdir -p "$DROP"
# name MUST be last so it wins
sudo tee "$DROP/zzzz-999-final.conf" >/dev/null <<EOF
[Service]
# P3K26_FINAL_SYSTEMD_V22F
Type=simple
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui

# clear everything that other drop-ins may set
ExecStart=
ExecStartPre=
ExecStartPost=
ExecStop=
ExecStopPost=
PIDFile=

# make sure pid dir exists before start
ExecStartPre=/bin/bash -lc 'mkdir -p ${OUT} && chmod 775 ${OUT} || true'

# run gunicorn foreground + real pidfile
ExecStart=${GUNI} --workers 2 --threads 4 --worker-class gthread --bind ${BIND} --pid ${PIDFILE} ${MOD}:${CALLABLE}

Restart=always
RestartSec=2
EOF
echo "[OK] wrote $DROP/zzzz-999-final.conf"

echo "== [3] daemon-reload + hard restart =="
sudo systemctl daemon-reload
sudo systemctl stop "$SVC" || true
sudo systemctl reset-failed "$SVC" || true

# kill anything still holding port (rare)
ss -lptn "sport = :$PORT" || true
PIDS="$(ss -lptn "sport = :$PORT" 2>/dev/null | awk -F'pid=|,' '/pid=/{print $2}' | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// }" ]; then
  echo "[WARN] port $PORT still in use by: $PIDS (killing)"
  for p in $PIDS; do sudo kill -TERM "$p" 2>/dev/null || true; done
  sleep 1
  for p in $PIDS; do sudo kill -KILL "$p" 2>/dev/null || true; done
fi

sudo systemctl start "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"

echo "== [4] verify unit + listen + pidfile =="
if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze verify "/etc/systemd/system/${SVC}" 2>&1 | tail -n 80 || true
fi
sudo systemctl status "$SVC" -n 25 --no-pager || true
ss -lptn "sport = :$PORT" || true
ls -l "$PIDFILE" 2>/dev/null || echo "[WARN] pidfile missing: $PIDFILE"
( cat "$PIDFILE" 2>/dev/null || true ) | head -c 80; echo

echo "== [5] smoke (5s) =="
curl -fsS --connect-timeout 1 --max-time 5 "$BASE/api/vsp/rid_latest" | head -c 220; echo || true
