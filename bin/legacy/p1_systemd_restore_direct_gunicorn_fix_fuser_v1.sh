#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need date; need mkdir; need tee; need sed; need ss; need curl

TS="$(date +%Y%m%d_%H%M%S)"
UNIT="vsp-ui-8910.service"
DROP="/etc/systemd/system/${UNIT}.d"
OVR="${DROP}/override.conf"

sudo mkdir -p "$DROP"

# backup old override if exists
if sudo test -f "$OVR"; then
  sudo cp -f "$OVR" "${OVR}.bak_${TS}"
  echo "[BACKUP] ${OVR}.bak_${TS}"
fi

# Write a minimal override: DO NOT touch ExecStart (so base unit's direct gunicorn stays)
# Only fix ExecStopPost to avoid /usr/sbin/fuser missing.
sudo tee "$OVR" >/dev/null <<'EOF'
[Service]
ExecStopPost=
ExecStopPost=/usr/bin/env bash -lc 'command -v fuser >/dev/null 2>&1 && fuser -k 8910/tcp || true'
EOF

echo "[OK] wrote override: $OVR (keeps base ExecStart=gunicorn wsgi_vsp_ui_gateway:application)"
sudo systemctl daemon-reload
sudo systemctl restart "$UNIT"

echo "== status (top) =="
sudo systemctl status "$UNIT" --no-pager | sed -n '1,22p' || true

echo "== ss :8910 =="
ss -ltnp | egrep '(:8910)\b' || true

echo "== probe /vsp5 =="
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,12p' || true
