#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/vsp-ui-8910.service"

mkdir -p "$UNIT_DIR"

# build info (optional)
GIT_HASH="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$UNIT" <<EOF
[Unit]
Description=VSP UI Gateway (8910)
After=network.target

[Service]
Type=simple
WorkingDirectory=$ROOT
Environment=VSP_GIT_HASH=$GIT_HASH
Environment=VSP_BUILD_TIME=$BUILD_TIME
# Nếu bạn dùng venv riêng:
ExecStart=/usr/bin/env bash -lc 'cd $ROOT && source ../.venv/bin/activate 2>/dev/null || true; exec python3 vsp_demo_app.py'
Restart=always
RestartSec=2
# log cố định (append) – nếu systemd bạn không support append:, đổi sang journal
StandardOutput=append:$ROOT/out_ci/ui_8910.log
StandardError=append:$ROOT/out_ci/ui_8910.log

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now vsp-ui-8910.service

echo "[OK] service started"
echo "  status: systemctl --user status vsp-ui-8910.service --no-pager"
echo "  logs  : tail -f $ROOT/out_ci/ui_8910.log"
echo "  health: curl -sS http://127.0.0.1:8910/healthz"
echo "  ver   : curl -sS http://127.0.0.1:8910/api/vsp/version | jq"
