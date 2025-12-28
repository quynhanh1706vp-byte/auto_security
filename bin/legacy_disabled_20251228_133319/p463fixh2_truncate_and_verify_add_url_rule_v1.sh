#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p463fixh2_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need date; need curl; need head; need grep
command -v sudo >/dev/null 2>&1 || { echo "[ERR] need sudo" | tee -a "$OUT/log.txt"; exit 2; }
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl" | tee -a "$OUT/log.txt"; exit 2; }

ERRLOG="out_ci/ui_8910.error.log"
[ -f "$ERRLOG" ] || { echo "[ERR] missing $ERRLOG" | tee -a "$OUT/log.txt"; exit 2; }

echo "[INFO] snapshot old error log => $OUT/ui_8910.error.log.before" | tee -a "$OUT/log.txt"
cp -f "$ERRLOG" "$OUT/ui_8910.error.log.before" || true

echo "[INFO] TRUNCATE error log" | tee -a "$OUT/log.txt"
: > "$ERRLOG"

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" || true
sleep 1
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true

echo "[INFO] hit a few endpoints" | tee -a "$OUT/log.txt"
curl -fsS --connect-timeout 1 --max-time 4 "$BASE/vsp5" >/dev/null || true
curl -fsS --connect-timeout 1 --max-time 6 "$BASE/api/vsp/sha256" | head -c 120 | tee -a "$OUT/log.txt" || true
echo "" | tee -a "$OUT/log.txt"
curl -sS -D- -o /dev/null --connect-timeout 1 --max-time 6 "$BASE/api/vsp/export_csv" | head -n 5 | tee -a "$OUT/log.txt" || true

sleep 1

echo "== NEW error log scan for add_url_rule AttributeError ==" | tee -a "$OUT/log.txt"
if grep -n "AttributeError: .*add_url_rule" "$ERRLOG" >/dev/null 2>&1; then
  echo "[FAIL] still producing add_url_rule AttributeError (NEW)" | tee -a "$OUT/log.txt"
  grep -n "AttributeError: .*add_url_rule" -n "$ERRLOG" | tail -n 10 | tee -a "$OUT/log.txt" || true
  echo "---- context (last 120 lines) ----" | tee -a "$OUT/log.txt"
  tail -n 120 "$ERRLOG" | tee "$OUT/ui_8910.error.log.after_tail.txt" >/dev/null || true
  exit 3
else
  echo "[OK] no NEW add_url_rule AttributeError after truncate+restart" | tee -a "$OUT/log.txt"
fi

echo "[OK] DONE: $OUT/log.txt" | tee -a "$OUT/log.txt"
