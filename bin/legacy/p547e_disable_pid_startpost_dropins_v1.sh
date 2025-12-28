#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="vsp-ui-8910.service"
DD="/etc/systemd/system/${SVC}.d"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need python3; need grep; need mv; need ls

# 0) ensure out_ci exists
sudo install -d -m 0775 -o test -g test /home/test/Data/SECURITY_BUNDLE/ui/out_ci

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

# 2) disable any drop-in that sets PIDFile or ExecStartPost (backup then rename)
sudo mkdir -p "$DD"
hits="$(sudo grep -RIl -E '^\s*PIDFile\s*=|^\s*ExecStartPost\s*=|ui_8910\.pid' "$DD" 2>/dev/null || true)"
if [ -n "$hits" ]; then
  echo "[INFO] disabling drop-ins:"
  echo "$hits" | sed 's/^/  - /'
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    sudo cp -f "$f" "${f}.bak_${TS}"
    sudo mv -f "$f" "${f}.disabled_${TS}"
    echo "[OK] disabled => $f"
  done <<< "$hits"
else
  echo "[OK] no PIDFile/ExecStartPost drop-in found"
fi

# 3) enforce "simple + no pidfile + no start-post" via highest-priority drop-in
FORCE="$DD/99-force-simple.conf"
sudo tee "$FORCE" >/dev/null <<'EOF'
[Service]
Type=simple
User=test
Group=test

# hard reset any legacy pid/start-post logic
PIDFile=
ExecStartPre=
ExecStartPost=
ExecStop=
ExecStopPost=

ExecStart=
ExecStart=/bin/bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_start.sh
EOF
echo "[OK] wrote $FORCE"

sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

echo "== effective =="
SYSTEMD_PAGER=cat sudo systemctl show -p DropInPaths,Type,PIDFile,ExecStart,ExecStartPost "$SVC"
sudo systemctl is-active "$SVC"
