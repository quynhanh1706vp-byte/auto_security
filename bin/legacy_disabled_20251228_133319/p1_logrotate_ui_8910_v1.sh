#!/usr/bin/env bash
set -euo pipefail
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need sudo; need tee

TS="$(date +%Y%m%d_%H%M%S)"
CONF="/etc/logrotate.d/vsp-ui-8910"
sudo test -f "$CONF" && sudo cp -f "$CONF" "${CONF}.bak_${TS}" && echo "[BACKUP] ${CONF}.bak_${TS}" || true

sudo tee "$CONF" >/dev/null <<'EOF'
/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.boot.log
/home/test/Data/SECURITY_BUNDLE/ui/nohup.out {
  daily
  rotate 14
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
  size 5M
  create 0644 test test
}
EOF

echo "[OK] wrote $CONF"
echo "[HINT] dry-run:"
sudo logrotate -d "$CONF" | tail -n 40 || true
