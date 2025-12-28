#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p517_rescue_${TS}"
mkdir -p "$OUT"
log(){ echo "$*" | tee -a "$OUT/log.txt"; }

BK="$(ls -1t out_ci/p516_*/${APP}.bak_* 2>/dev/null | head -n1 || true)"
[ -n "$BK" ] || { log "[ERR] cannot find p516 backup for $APP"; exit 2; }

log "[INFO] restore $APP from $BK"
cp -f "$BK" "$APP"
python3 -m py_compile "$APP" && log "[OK] py_compile $APP"

log "[INFO] reset-failed + restart $SVC"
sudo systemctl reset-failed "$SVC" || true
sudo systemctl restart "$SVC" || true
sleep 1

sudo systemctl status "$SVC" --no-pager | tee "$OUT/systemctl_status.txt" || true
sudo journalctl -u "$SVC" -n 120 --no-pager | tee "$OUT/journal_tail.txt" || true

log "[INFO] probe $BASE/c/dashboard"
curl -sS -D "$OUT/probe_dashboard.hdr" -o /dev/null "$BASE/c/dashboard" || true
head -n 12 "$OUT/probe_dashboard.hdr" | tee -a "$OUT/log.txt" || true

log "[DONE] OUT=$OUT"
