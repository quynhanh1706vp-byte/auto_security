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
command -v curl >/dev/null 2>&1 || true

mkdir -p "$OUT"

echo "== [0] detect WSGI callable (application/app) =="
CALLABLE="$(python3 - <<'PY'
import importlib, sys
m=importlib.import_module("wsgi_vsp_ui_gateway")
if hasattr(m,"application"): print("application")
elif hasattr(m,"app"): print("app")
else:
    # fallback to "application" (your gateway prints it wraps both)
    print("application")
PY
)"
echo "[OK] callable=${MOD}:${CALLABLE}"

echo "== [1] pick gunicorn binary (venv preferred) =="
GUNI="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn"
if [ ! -x "$GUNI" ]; then
  GUNI="$(command -v gunicorn || true)"
fi
[ -n "${GUNI:-}" ] || { echo "[ERR] gunicorn not found"; exit 2; }
echo "[OK] gunicorn=$GUNI"

echo "== [2] create systemd drop-in override =="
DROP="/etc/systemd/system/${SVC}.d"
sudo mkdir -p "$DROP"
sudo tee "$DROP/override.conf" >/dev/null <<EOF
[Service]
# P3K26_SYSTEMD_SIMPLE_PID_V22
Type=simple
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui

# clear any old ExecStart/ExecStartPost that may exit 3 or rely on stale PIDFile
ExecStart=
ExecStartPost=
PIDFile=

# run gunicorn in foreground, write real pid
ExecStart=${GUNI} --workers 2 --threads 4 --worker-class gthread --bind ${BIND} --pid ${PIDFILE} ${MOD}:${CALLABLE}

Restart=always
RestartSec=2
EOF
echo "[OK] wrote $DROP/override.conf"

echo "== [3] reload + restart =="
sudo systemctl daemon-reload
sudo systemctl reset-failed "$SVC" || true
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"

echo "== [4] quick status + pidfile =="
sudo systemctl status "$SVC" -n 30 --no-pager || true
echo "[INFO] pidfile exists?"; ls -l "$PIDFILE" || true
echo "[INFO] pid inside?"; (cat "$PIDFILE" || true) | head -c 80; echo

echo "== [5] smoke (5s) =="
curl -fsS --connect-timeout 1 --max-time 5 "$BASE/api/vsp/rid_latest" | head -c 300; echo
