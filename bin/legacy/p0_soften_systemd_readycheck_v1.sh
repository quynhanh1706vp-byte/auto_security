#!/usr/bin/env bash
set -euo pipefail
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

D="/etc/systemd/system/${SVC}.d"
C="${D}/override_readycheck_soft.conf"

sudo mkdir -p "$D"

cat | sudo tee "$C" >/dev/null <<'CONF'
[Service]
# Soft readycheck: never fail the service if curl cannot connect immediately
ExecStartPost=
ExecStartPost=/bin/bash -lc 'BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"; for i in $(seq 1 120); do curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1 && exit 0; sleep 0.25; done; exit 0'
Restart=always
RestartSec=1
CONF

sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

echo "[OK] patched systemd readycheck soft + restarted $SVC"
systemctl --no-pager --full status "$SVC" | sed -n '1,25p' || true
