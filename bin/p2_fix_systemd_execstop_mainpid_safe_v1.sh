#!/usr/bin/env bash
set -euo pipefail

SVC="vsp-ui-8910.service"
D="/etc/systemd/system/${SVC}.d"
F="${D}/override_execstop_safe.conf"
TS="$(date +%Y%m%d_%H%M%S)"

echo "[INFO] writing drop-in: $F"
sudo -v

sudo mkdir -p "$D"
if sudo test -f "$F"; then
  sudo cp -f "$F" "${F}.bak_${TS}"
  echo "[BACKUP] ${F}.bak_${TS}"
fi

# Clear any previous ExecStop=, then add a safe one.
sudo tee "$F" >/dev/null <<'CONF'
[Service]
ExecStop=
ExecStop=/bin/bash -lc 'if [ -n "${MAINPID:-}" ]; then kill -TERM "$MAINPID" 2>/dev/null || true; fi; exit 0'
CONF

sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true

echo "== status =="
sudo systemctl is-active "$SVC" && echo "[OK] active"
sudo systemctl is-failed "$SVC" && echo "[WARN] still failed (check journal)" || true
