#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT=out_ci; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_umask027_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need date; need sudo; need systemctl; need grep; need mkdir; need cp; need cat; need curl

OVDIR="/etc/systemd/system/${SVC}.d"
OVCONF="${OVDIR}/override.conf"
sudo mkdir -p "$OVDIR"

echo "== [P47.2] set UMask=027 ==" | tee "$LOG"
echo "svc=$SVC" | tee -a "$LOG"

if sudo test -f "$OVCONF"; then
  sudo cp -f "$OVCONF" "${OVCONF}.bak_umask_${TS}"
  echo "[OK] backup: ${OVCONF}.bak_umask_${TS}" | tee -a "$LOG"
fi

# write/merge: ensure [Service] + UMask=027 exists
tmp="$OUT/override_umask_${TS}.conf"
sudo bash -lc "cat > '$tmp' <<'CONF'
[Service]
UMask=027
CONF"

if sudo test -f "$OVCONF"; then
  # if already has UMask, replace; else append
  if sudo grep -q '^UMask=' "$OVCONF"; then
    sudo sed -i 's/^UMask=.*/UMask=027/' "$OVCONF"
    echo "[OK] updated existing UMask" | tee -a "$LOG"
  else
    sudo bash -lc "printf '\nUMask=027\n' >> '$OVCONF'"
    echo "[OK] appended UMask" | tee -a "$LOG"
  fi
else
  sudo cp -f "$tmp" "$OVCONF"
  echo "[OK] created override.conf" | tee -a "$LOG"
fi

echo "== override preview ==" | tee -a "$LOG"
sudo cat "$OVCONF" | tail -n 40 | tee -a "$LOG" >/dev/null || true

echo "== reload + restart ==" | tee -a "$LOG"
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true

# quick probe
code=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 http://127.0.0.1:8910/vsp5 || true)
echo "probe /vsp5=$code" | tee -a "$LOG"
[ "$code" = "200" ] && echo "[OK] DONE" | tee -a "$LOG" || { echo "[WARN] service not 200 (see $LOG)" | tee -a "$LOG"; exit 2; }
