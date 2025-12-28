#!/usr/bin/env bash
set -euo pipefail
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PORT=8910
OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci"
PIDFILE="${OUT}/ui_${PORT}.pid"

sudo mkdir -p "$OUT"
sudo chmod 775 "$OUT" || true
sudo chown -R "$USER":"$USER" "$OUT" || true

# nếu unit dùng PIDFile, file rỗng vẫn giúp start-post không fail
: | sudo tee "$PIDFILE" >/dev/null || true
sudo chmod 664 "$PIDFILE" || true
echo "[OK] ensured pidfile path: $PIDFILE"

sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
