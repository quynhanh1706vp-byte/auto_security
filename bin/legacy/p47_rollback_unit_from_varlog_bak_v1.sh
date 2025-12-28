#!/usr/bin/env bash
set -euo pipefail
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_rollback_unit_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need date; need sudo; need systemctl; need ls; need head; need cp; need curl; need tail

UNIT="/etc/systemd/system/${SVC}"
bak="$(ls -1t ${UNIT}.bak_varlog_* 2>/dev/null | head -n 1 || true)"
[ -n "$bak" ] || { echo "[FAIL] no ${UNIT}.bak_varlog_* found" | tee -a "$LOG"; exit 2; }

echo "== [ROLLBACK UNIT] svc=$SVC ==" | tee "$LOG"
echo "[OK] restore from: $bak" | tee -a "$LOG"
sudo cp -f "$UNIT" "${UNIT}.bad_${TS}" || true
sudo cp -f "$bak" "$UNIT"

sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true

code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$BASE/vsp5" 2>/dev/null || true)"
echo "probe /vsp5=$code" | tee -a "$LOG"
[ "$code" = "200" ] || { systemctl status "$SVC" --no-pager | tail -n 120 | tee -a "$LOG" >/dev/null; exit 2; }

echo "[OK] DONE: $LOG" | tee -a "$LOG"
