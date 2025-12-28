#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="vsp-ui-8910.service"
DROP_DIR="/etc/systemd/system/${SVC}.d"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need bash; need cat; need mkdir; need install

# 0) ensure out_ci exists and writable
sudo install -d -m 0775 -o test -g test /home/test/Data/SECURITY_BUNDLE/ui/out_ci

# 1) rewrite CLEAN wrapper (no garbage)
cat > bin/vsp_ui_start.sh <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

CFG="/home/test/Data/SECURITY_BUNDLE/ui/config/production.env"
if [ -f "$CFG" ]; then
  set +u
  # shellcheck disable=SC1090
  source "$CFG"
  set -u
fi

HOST="${VSP_UI_HOST:-127.0.0.1}"
PORT="${VSP_UI_PORT:-8910}"
WORKERS="${VSP_UI_WORKERS:-2}"
APP="${VSP_UI_WSGI_APP:-wsgi_vsp_ui_gateway:app}"

VENV_GUNICORN="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn"

if [ -x "$VENV_GUNICORN" ]; then
  exec "$VENV_GUNICORN" -b "${HOST}:${PORT}" -w "${WORKERS}" "$APP"
fi

exec /usr/bin/python3 -m gunicorn -b "${HOST}:${PORT}" -w "${WORKERS}" "$APP"
WRAP

chmod +x bin/vsp_ui_start.sh
bash -n bin/vsp_ui_start.sh
echo "[OK] wrapper OK"

# 2) hard override: remove PIDFile + start-post hooks (reset by empty assignment)
sudo mkdir -p "$DROP_DIR"
OVR="$DROP_DIR/99-nopidfile.conf"
sudo cp -f "$OVR" "${OVR}.bak_${TS}" 2>/dev/null || true

cat > /tmp/${SVC}.${TS}.conf <<EOF
[Service]
Type=simple
User=test
Group=test

# Reset any PID/start-post logic from older drop-ins
PIDFile=
ExecStartPre=
ExecStartPost=
ExecStop=
ExecStopPost=

# Force stable ExecStart
ExecStart=
ExecStart=/bin/bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_start.sh
EOF

sudo mv -f /tmp/${SVC}.${TS}.conf "$OVR"
echo "[OK] wrote $OVR"

# 3) reload + restart
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

# 4) show effective config
SYSTEMD_PAGER=cat sudo systemctl show -p DropInPaths,Type,PIDFile,ExecStart,ExecStartPost "$SVC"
sudo systemctl is-active "$SVC"
