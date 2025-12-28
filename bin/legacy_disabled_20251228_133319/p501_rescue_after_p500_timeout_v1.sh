#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p501_rescue_${TS}"
mkdir -p "$OUT"

log(){ echo "$*" | tee -a "$OUT/log.txt"; }

T="wsgi_vsp_ui_gateway.py"
[ -f "$T" ] || T="vsp_demo_app.py"
[ -f "$T" ] || { log "[ERR] missing wsgi_vsp_ui_gateway.py and vsp_demo_app.py"; exit 2; }

# find latest p500 backup for the chosen target
BK="$(ls -1t out_ci/p500_*/$(basename "$T").bak_* 2>/dev/null | head -n1 || true)"
if [ -z "$BK" ]; then
  log "[ERR] cannot find p500 backup for $T under out_ci/p500_*/"
  log "[HINT] list: ls -1t out_ci/p500_* | head"
  exit 3
fi

log "[INFO] target=$T"
log "[INFO] restore_from=$BK"
cp -f "$BK" "$T"
log "[OK] restored $T"

# syntax check
python3 -m py_compile "$T" && log "[OK] py_compile $T" || { log "[ERR] py_compile failed $T"; exit 4; }

# restart service
log "[INFO] reset-failed + restart $SVC"
sudo systemctl reset-failed "$SVC" || true
if ! sudo systemctl restart "$SVC"; then
  log "[ERR] restart failed (collect status/journal)"
fi

sleep 1
sudo systemctl status "$SVC" --no-pager | tee "$OUT/systemctl_status.txt" || true
sudo journalctl -u "$SVC" -n 200 --no-pager | tee "$OUT/journal_tail.txt" || true

# quick health probes
log "[INFO] probe $BASE/c/dashboard"
curl -sS -D "$OUT/probe_dashboard.hdr" -o /dev/null "$BASE/c/dashboard" || true
head -n 12 "$OUT/probe_dashboard.hdr" | tee -a "$OUT/log.txt" || true

log "[INFO] probe $BASE/api/vsp/runs_v3"
curl -sS -D "$OUT/probe_runsv3.hdr" -o "$OUT/probe_runsv3.body" "$BASE/api/vsp/runs_v3?limit=1&include_ci=1" || true
head -n 12 "$OUT/probe_runsv3.hdr" | tee -a "$OUT/log.txt" || true
head -c 200 "$OUT/probe_runsv3.body" | tee -a "$OUT/log.txt" || true
echo "" | tee -a "$OUT/log.txt"

log "[DONE] OUT=$OUT"
