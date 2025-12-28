#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PORT=8910
BIND="127.0.0.1:${PORT}"
OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci"
PIDFILE="${OUT}/ui_${PORT}.pid"
MOD="wsgi_vsp_ui_gateway"
DIR="/etc/systemd/system/${SVC}.d"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo
need systemctl
need python3
command -v ss >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

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

echo "== [2] backup all drop-ins =="
sudo mkdir -p "$DIR"
sudo tar -C "$DIR" -czf "/tmp/${SVC}.dropins_bak_${TS}.tgz" . || true
echo "[OK] backup => /tmp/${SVC}.dropins_bak_${TS}.tgz"

echo "== [3] disable ALL drop-ins except zzzz-999-final.conf (rename to .disabled_TS) =="
for f in $(sudo ls -1 "$DIR"/*.conf 2>/dev/null || true); do
  bn="$(basename "$f")"
  if [ "$bn" = "zzzz-999-final.conf" ]; then
    continue
  fi
  sudo mv -f "$f" "${f}.disabled_${TS}" || true
done

echo "== [4] rewrite zzzz-999-final.conf to MINIMAL CLEAN content (no logs/comments) =="
sudo tee "$DIR/zzzz-999-final.conf" >/dev/null <<EOF
[Service]
Type=simple
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui

# Clear inherited start hooks from base unit or older drop-ins
ExecStart=
ExecStartPre=
ExecStartPost=
PIDFile=

ExecStartPre=/bin/bash -lc 'mkdir -p ${OUT} && chmod 775 ${OUT} || true'
ExecStart=${GUNI} --workers 2 --threads 4 --worker-class gthread --bind ${BIND} --pid ${PIDFILE} ${MOD}:${CALLABLE}

Restart=always
RestartSec=2
EOF
echo "[OK] wrote clean $DIR/zzzz-999-final.conf"

echo "== [5] reload + restart + smoke =="
sudo systemctl daemon-reload
sudo systemctl reset-failed "$SVC" || true
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"

ss -lptn "sport = :${PORT}" || true
curl -fsS --connect-timeout 1 --max-time 5 "http://${BIND}/api/vsp/rid_latest" | head -c 220; echo || true

echo "[DONE] v24c"
