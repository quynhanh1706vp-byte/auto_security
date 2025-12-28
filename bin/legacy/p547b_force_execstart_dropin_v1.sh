#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="vsp-ui-8910.service"
DROP_DIR="/etc/systemd/system/${SVC}.d"
DROP="${DROP_DIR}/override.conf"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need bash; need cat; need mkdir; need ls

# 1) write a CLEAN wrapper (no env dependency)
sudo mkdir -p /home/test/Data/SECURITY_BUNDLE/ui/bin >/dev/null 2>&1 || true

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

# fallback: system python gunicorn (if installed)
if command -v /usr/bin/python3 >/dev/null 2>&1; then
  exec /usr/bin/python3 -m gunicorn -b "${HOST}:${PORT}" -w "${WORKERS}" "$APP"
fi

echo "[FATAL] cannot start: no gunicorn found" >&2
exit 203
WRAP

chmod +x bin/vsp_ui_start.sh
echo "[OK] wrote bin/vsp_ui_start.sh"

# 2) create systemd drop-in override for ExecStart (this ALWAYS wins)
sudo mkdir -p "$DROP_DIR"
if [ -f "$DROP" ]; then
  sudo cp -f "$DROP" "${DROP}.bak_${TS}"
  echo "[OK] backup => ${DROP}.bak_${TS}"
fi

cat > /tmp/vsp_override_${TS}.conf <<EOF
[Service]
User=test
Group=test

# Reset then set ExecStart (systemd requires blank ExecStart= first)
ExecStart=
ExecStart=/bin/bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_start.sh
EOF

sudo mv -f /tmp/vsp_override_${TS}.conf "$DROP"
echo "[OK] wrote $DROP"

# 3) reload + restart
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" >/dev/null
echo "[OK] restarted $SVC"

# 4) prove the override is in effect
SYSTEMD_PAGER=cat sudo systemctl show -p FragmentPath,DropInPaths,ExecStart,User,Group "$SVC"
