#!/usr/bin/env bash
set -euo pipefail
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need mkdir; need tee

UNIT="vsp-ui-8910.service"
DROP="/etc/systemd/system/${UNIT}.d"
OVR="${DROP}/override.conf"

sudo mkdir -p "$DROP"

sudo tee "$OVR" >/dev/null <<'EOF'
[Service]
# reset ExecStart (systemd override requirement)
ExecStart=
ExecStart=/usr/bin/env bash /home/test/Data/SECURITY_BUNDLE/ui/bin/p1_ui_8910_single_owner_start_v2.sh
Restart=always
RestartSec=2
TimeoutStartSec=30
TimeoutStopSec=10
KillSignal=SIGTERM
EOF

echo "[OK] wrote $OVR"
sudo systemctl daemon-reload
sudo systemctl restart "$UNIT" || true
sudo systemctl status "$UNIT" --no-pager | sed -n '1,18p' || true
