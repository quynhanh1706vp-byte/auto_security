#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_logrotate_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need date; need sudo; need logrotate; need head; need grep; need ls; need stat

RULE="/etc/logrotate.d/vsp-ui-8910"
STATE="/var/lib/logrotate/status"
CONF_TMP="$OUT/p47_logrotate_conf_${TS}.conf"

echo "== [P47.1] logrotate hardening ==" | tee "$LOG"
echo "[INFO] SVC=$SVC" | tee -a "$LOG"
echo "[INFO] RULE=$RULE" | tee -a "$LOG"

# backup existing rule
if sudo test -f "$RULE"; then
  sudo cp -f "$RULE" "${RULE}.bak_${TS}"
  echo "[OK] backup: ${RULE}.bak_${TS}" | tee -a "$LOG"
fi

# write rule (rotate by size + keep history; copytruncate so gunicorn keeps writing)
cat > "$CONF_TMP" <<'CONF'
/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log
/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.access.log
{
  daily
  rotate 14
  size 20M
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
  dateext
  dateformat -%Y%m%d_%H%M%S
  maxage 30
  create 0640 test test
}
CONF

sudo cp -f "$CONF_TMP" "$RULE"
sudo chmod 0644 "$RULE"

echo "[OK] wrote rule: $RULE" | tee -a "$LOG"
echo "== rule preview ==" | tee -a "$LOG"
sudo head -n 60 "$RULE" | tee -a "$LOG" >/dev/null || true

# dry-run
echo "== dry run ==" | tee -a "$LOG"
sudo logrotate -d -s "$STATE" "$RULE" 2>&1 | tail -n 80 | tee -a "$LOG" >/dev/null || true

# force run once (safe with copytruncate)
echo "== force run ==" | tee -a "$LOG"
sudo logrotate -f -s "$STATE" "$RULE" 2>&1 | tail -n 120 | tee -a "$LOG" >/dev/null || true

echo "== after ==" | tee -a "$LOG"
ls -lh out_ci/ui_8910.*log* 2>/dev/null | tee -a "$LOG" >/dev/null || true

echo "[OK] log: $LOG"
echo "[OK] DONE"
