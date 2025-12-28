#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
DD="/etc/systemd/system/${SVC}.d"
CONF="${DD}/01-official.conf"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need awk; need sed; need curl

echo "[P548b] force-clear ExecStartPost/PIDFile for $SVC"
sudo install -d -m 0755 "$DD"

# backup old conf if exists
if sudo test -f "$CONF"; then
  sudo cp -f "$CONF" "${CONF}.bak_${TS}"
  echo "[OK] backup => ${CONF}.bak_${TS}"
fi

# IMPORTANT: reset list-type directives by assigning empty
sudo tee "$CONF" >/dev/null <<'EOF'
[Service]
# commercial: do NOT use pidfile / start-post
Type=simple
PIDFile=

ExecStartPre=
ExecStartPost=
ExecStopPost=

# keep UMask/Restart if already set in main unit, but safe to re-assert
UMask=0027
Restart=always
RestartSec=2
TimeoutStartSec=25
EOF
echo "[OK] wrote $CONF"

echo "== daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true
sleep 1

echo "== effective fields =="
sudo systemctl show -p Type,PIDFile,ExecStart,ExecStartPre,ExecStartPost,ExecStopPost,DropInPaths "$SVC" | sed 's/; /\n  /g'

echo "== journal tail =="
sudo journalctl -u "$SVC" --since "2 min ago" --no-pager | tail -n 80 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== health probe: $BASE =="
for i in 1 2 3 4 5; do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null; then
    echo "[OK] UI up: $BASE/vsp5"
    exit 0
  fi
  sleep 1
done

echo "[FAIL] UI still down on $BASE"
exit 2
