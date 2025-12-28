#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="vsp-ui-8910.service"
DD="/etc/systemd/system/${SVC}.d"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need python3; need mv; need ls; need mkdir

# 1) rewrite wrapper CLEAN via python (no heredoc corruption)
python3 - <<'PY'
from pathlib import Path
p = Path("/home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_start.sh")
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text("""#!/usr/bin/env bash
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
""", encoding="utf-8")
print("[OK] wrote", p)
PY
chmod +x bin/vsp_ui_start.sh
bash -n bin/vsp_ui_start.sh
echo "[OK] wrapper syntax OK"

# 2) disable 00-known-good.conf (nếu tồn tại) vì nó đang giữ PID/start-post logic
sudo mkdir -p "$DD"
if [ -f "$DD/00-known-good.conf" ]; then
  sudo cp -f "$DD/00-known-good.conf" "$DD/00-known-good.conf.bak_${TS}"
  sudo mv -f "$DD/00-known-good.conf" "$DD/00-known-good.conf.disabled_${TS}"
  echo "[OK] disabled 00-known-good.conf (backup kept)"
fi

# 3) ensure nopidfile override exists (idempotent)
sudo tee "$DD/99-nopidfile.conf" >/dev/null <<'EOF'
[Service]
Type=simple
User=test
Group=test

PIDFile=
ExecStartPre=
ExecStartPost=
ExecStop=
ExecStopPost=

ExecStart=
ExecStart=/bin/bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_start.sh
EOF
echo "[OK] ensured 99-nopidfile.conf"

# 4) reload + restart + prove effective
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" >/dev/null
echo "[OK] service active"

SYSTEMD_PAGER=cat sudo systemctl show -p DropInPaths,Type,PIDFile,ExecStart,ExecStartPost "$SVC"
