#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="vsp-ui-8910.service"
DD="/etc/systemd/system/${SVC}.d"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need ls; need grep; need awk; need sed

echo "[P548] hard reset drop-ins: $SVC"

# 1) Disable EVERY drop-in except the one we will create (01-official.conf)
sudo install -d -m 0755 "$DD"
for f in $(sudo ls -1 "$DD"/*.conf 2>/dev/null || true); do
  base="$(basename "$f")"
  if [ "$base" != "01-official.conf" ]; then
    sudo mv -f "$f" "$f.disabled_${TS}"
    echo "[OK] disabled => $f.disabled_${TS}"
  fi
done

# 2) Write official drop-in: clear PIDFile + ExecStartPost, set ExecStart directly
#    IMPORTANT: "ExecStart=" (empty) line clears all previous ExecStart in drop-ins.
sudo tee "$DD/01-official.conf" >/dev/null <<EOF
[Service]
User=test
Group=test
Type=simple
WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui
EnvironmentFile=/home/test/Data/SECURITY_BUNDLE/ui/config/production.env

# Clear all inherited start-post + PIDFile to avoid timeout/203
ExecStartPost=
PIDFile=

# Clear inherited ExecStart then set only one official ExecStart
ExecStart=
ExecStart=/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application --workers 2 --worker-class gthread --threads 8 --timeout 120 --graceful-timeout 15 --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui --bind 127.0.0.1:8910 --access-logfile /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.access.log --error-logfile /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log --keep-alive 5
EOF
echo "[OK] wrote $DD/01-official.conf"

# 3) Ensure out_ci exists + permissions
sudo install -d -m 0775 -o test -g test /home/test/Data/SECURITY_BUNDLE/ui/out_ci

# 4) Reload + restart + show effective fields
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

echo "== effective fields =="
SYSTEMD_PAGER=cat sudo systemctl show -p Type,PIDFile,ExecStart,ExecStartPost,DropInPaths,User,Group "$SVC" | sed 's/;.*$//'

echo "== journal tail =="
sudo journalctl -u "$SVC" -n 30 --no-pager

echo "== health/ready =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS "$BASE/api/healthz" && echo
curl -fsS "$BASE/api/readyz"  && echo

echo "[P548] DONE"
