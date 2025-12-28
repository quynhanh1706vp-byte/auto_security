#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PORT=8910
BIND="0.0.0.0:${PORT}"   # giữ giống hiện tại bạn đang LISTEN 0.0.0.0:8910
OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci"
PIDFILE="${OUT}/ui_${PORT}.pid"
DIR="/etc/systemd/system/${SVC}.d"
FINAL="${DIR}/zzzz-999-final.conf"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo
need systemctl
need ss
command -v curl >/dev/null 2>&1 || true

GUNI="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn"
if [ ! -x "$GUNI" ]; then
  GUNI="$(command -v gunicorn || true)"
fi
[ -n "${GUNI:-}" ] || { echo "[ERR] gunicorn not found"; exit 2; }

echo "== [1] backup current final drop-in =="
sudo mkdir -p "$DIR"
if [ -f "$FINAL" ]; then
  sudo cp -f "$FINAL" "${FINAL}.bak_v24d_${TS}"
  echo "[OK] backup => ${FINAL}.bak_v24d_${TS}"
fi

echo "== [2] write CLEAN final drop-in (NO import, NO logs) =="
sudo tee "$FINAL" >/dev/null <<EOF
[Service]
Type=simple
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui

ExecStart=
ExecStartPre=
ExecStartPost=
ExecStop=
ExecStopPost=
PIDFile=

ExecStartPre=/bin/bash -lc 'mkdir -p ${OUT} && chmod 775 ${OUT} || true'
ExecStart=${GUNI} --workers 2 --threads 4 --worker-class gthread --bind ${BIND} --pid ${PIDFILE} wsgi_vsp_ui_gateway:application

Restart=always
RestartSec=2
EOF

echo "== [3] reload + restart =="
sudo systemctl daemon-reload
sudo systemctl reset-failed "$SVC" || true
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"

echo "== [4] verify + listen + smoke =="
systemd-analyze verify "/etc/systemd/system/${SVC}" 2>&1 | tail -n 60 || true
sudo systemctl status "$SVC" -n 20 --no-pager || true
ss -lptn "sport = :${PORT}" || true
curl -fsS --connect-timeout 1 --max-time 5 "http://127.0.0.1:${PORT}/api/vsp/rid_latest" | head -c 220; echo || true

echo "[DONE] v24d"
