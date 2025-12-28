#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
UI_DIR="/home/test/Data/SECURITY_BUNDLE/ui"
OUT_DIR="${UI_DIR}/out_ci"
PID_ABS="${OUT_DIR}/ui_8910.pid"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need awk; need grep; need sed; need curl

echo "== [0] ensure out_ci exists + perms =="
sudo mkdir -p "$OUT_DIR"
sudo chown -R test:test "$OUT_DIR" || true

echo "== [1] show current ExecStartPost/PIDFile (for visibility) =="
sudo systemctl cat "$SVC" | sed -n '1,220p' | grep -nE '^(PIDFile=|ExecStart=|ExecStartPost=|TimeoutStartSec=|TimeoutStopSec=)' || true

echo "== [2] install drop-in to hard-disable ready-check + make pid absolute =="
D="/etc/systemd/system/${SVC}.d"
sudo mkdir -p "$D"
sudo tee "$D/99-p3k24-no-readycheck-and-pid.conf" >/dev/null <<EOF
# === VSP_P3K24_NO_READYCHECK_AND_PID_V1 ===
[Service]
# kill the ready-check that can time out & terminate the service
ExecStartPost=
ExecStartPost=/bin/bash -lc 'exit 0'

# make sure pid path matches PIDFile and is absolute (avoid "Can't open PID file" races)
PIDFile=${PID_ABS}

# override ExecStart safely (systemd requires clearing then setting)
ExecStart=
ExecStart=${UI_DIR}/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application --workers 2 --log-level info --worker-class gthread --threads 4 --timeout 90 --graceful-timeout 20 --chdir ${UI_DIR} --pythonpath ${UI_DIR} --bind 127.0.0.1:8910 --pid ${PID_ABS} --access-logfile ${OUT_DIR}/ui_8910.access.log --error-logfile ${OUT_DIR}/ui_8910.error.log
EOF

echo "== [3] reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[FAIL] service not active"; sudo systemctl status "$SVC" --no-pager -l || true; exit 1; }

echo "== [4] smoke (fast) =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS --connect-timeout 1 --max-time 3 "$BASE/healthz" >/dev/null && echo "[OK] /healthz"
curl -fsS --connect-timeout 1 --max-time 6 "$BASE/vsp5"    >/dev/null && echo "[OK] /vsp5"
echo "[DONE] p3k24_fix_systemd_readycheck_pid_v1"
