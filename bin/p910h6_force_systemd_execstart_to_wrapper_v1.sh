#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
DROP="/etc/systemd/system/${SVC}.d"
CONF="${DROP}/p910h6-wrapper-execstart.conf"

echo "== [P910H6] current ExecStart (before) =="
sudo systemctl show -p ExecStart,FragmentPath "$SVC" --no-pager || true

echo "== [P910H6] ensure start script uses wrapper =="
grep -nE 'wsgi_vsp_p910h:app|vsp_demo_app:app' -n bin/vsp_ui_start.sh || true
# hard-force in case something reverted
python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/vsp_ui_start.sh")
s=p.read_text(encoding="utf-8", errors="replace")
s=re.sub(r'\bvsp_demo_app:app\b','wsgi_vsp_p910h:app',s)
p.write_text(s, encoding="utf-8")
print("[OK] ensured vsp_ui_start.sh -> wsgi_vsp_p910h:app")
PY
bash -n bin/vsp_ui_start.sh

echo "== [P910H6] write systemd drop-in override ExecStart =="
sudo mkdir -p "$DROP"
sudo tee "$CONF" >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=/home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_start.sh
EOF
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

echo "== [P910H6] wait ready =="
bash bin/ops/ops_restart_wait_ui_v1.sh

echo "== [P910H6] verify wrapper header MUST appear =="
curl -sS -D- -o /dev/null "$BASE/api/vsp/run_status_v1" | awk 'NR<=30'
echo
echo "== [P910H6] verify rid=undefined MUST be 200 + X-VSP-WRAP =="
curl -sS -D- -o /dev/null "$BASE/api/vsp/run_status_v1?rid=undefined" | awk 'NR<=30'

echo
echo "Open: $BASE/c/settings  (Ctrl+Shift+R)"
