#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="vsp-ui-8910.service"
UNIT="/etc/systemd/system/${SVC}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need python3; need systemctl; need grep; need sed; need head

# 1) create stable start wrapper
cat > bin/vsp_ui_start.sh <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

CFG="/home/test/Data/SECURITY_BUNDLE/ui/config/production.env"
[ -f "$CFG" ] && { set +u; source "$CFG"; set -u; } || true

HOST="${VSP_UI_HOST:-127.0.0.1}"
PORT="${VSP_UI_PORT:-8910}"
WORKERS="${VSP_UI_WORKERS:-2}"

# allow override app module if needed
APP="${VSP_UI_WSGI_APP:-wsgi_vsp_ui_gateway:app}"

VENV_GUNICORN="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn"

if [ -x "$VENV_GUNICORN" ]; then
  exec "$VENV_GUNICORN" -b "${HOST}:${PORT}" -w "${WORKERS}" "$APP"
fi

# fallback system python
if command -v /usr/bin/python3 >/dev/null 2>&1; then
  exec /usr/bin/python3 -m gunicorn -b "${HOST}:${PORT}" -w "${WORKERS}" "$APP"
fi

echo "[FATAL] no runnable gunicorn found (venv missing + python3 missing)" >&2
exit 203
WRAP
chmod +x bin/vsp_ui_start.sh
echo "[OK] wrote bin/vsp_ui_start.sh"

# 2) backup unit
sudo cp -f "$UNIT" "${UNIT}.bak_${TS}"
echo "[OK] backup => ${UNIT}.bak_${TS}"

# 3) patch unit: set ExecStart to wrapper; set User/Group to test (avoid empty)
sudo python3 - <<PY
from pathlib import Path
import re
p=Path("$UNIT")
s=p.read_text(encoding="utf-8", errors="replace")

# replace ExecStart line (even if old is complex)
if re.search(r'^\s*ExecStart\s*=', s, flags=re.M):
    s=re.sub(r'^\s*ExecStart\s*=.*$', 'ExecStart=/home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_start.sh', s, flags=re.M)
else:
    # insert ExecStart under [Service]
    s=re.sub(r'(\[Service\]\n)', r'\1ExecStart=/home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_start.sh\n', s, count=1)

# ensure WorkingDirectory
if not re.search(r'^\s*WorkingDirectory\s*=', s, flags=re.M):
    s=re.sub(r'(\[Service\]\n)', r'\1WorkingDirectory=/home/test/Data/SECURITY_BUNDLE/ui\n', s, count=1)

# ensure EnvironmentFile
if not re.search(r'^\s*EnvironmentFile\s*=', s, flags=re.M):
    s=re.sub(r'(\[Service\]\n)', r'\1EnvironmentFile=/home/test/Data/SECURITY_BUNDLE/ui/config/production.env\n', s, count=1)

# set User/Group if empty or missing
if re.search(r'^\s*User\s*=\s*$', s, flags=re.M) or not re.search(r'^\s*User\s*=', s, flags=re.M):
    if re.search(r'^\s*User\s*=\s*$', s, flags=re.M):
        s=re.sub(r'^\s*User\s*=\s*$', 'User=test', s, flags=re.M)
    else:
        s=re.sub(r'(\[Service\]\n)', r'\1User=test\n', s, count=1)

if re.search(r'^\s*Group\s*=\s*$', s, flags=re.M) or not re.search(r'^\s*Group\s*=', s, flags=re.M):
    if re.search(r'^\s*Group\s*=\s*$', s, flags=re.M):
        s=re.sub(r'^\s*Group\s*=\s*$', 'Group=test', s, flags=re.M)
    else:
        s=re.sub(r'(\[Service\]\n)', r'\1Group=test\n', s, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] patched unit")
PY

# 4) reload & restart
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" || { echo "[FAIL] service not active"; exit 2; }

echo "[OK] restarted $SVC"
SYSTEMD_PAGER=cat sudo systemctl show -p ExecStart,User,Group "$SVC"
