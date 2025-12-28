#!/usr/bin/env bash
set -u
cd /home/test/Data/SECURITY_BUNDLE/ui 2>/dev/null || { echo "[ERR] cd failed"; exit 0; }

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56f1_health_${TS}"
mkdir -p "$EVID"

echo "== [P56F1] BASE=$BASE SVC=$SVC ==" | tee "$EVID/summary.txt"

# 0) service status (non-fatal)
{
  echo "== systemctl status ==";
  systemctl status "$SVC" --no-pager -l || true;
  echo;
  echo "== systemctl show (key) ==";
  systemctl show "$SVC" -p ActiveState -p SubState -p MainPID -p ExecMainStatus -p ExecMainCode --no-pager || true;
} > "$EVID/systemctl.txt" 2>&1

# 1) quick journal tail (non-fatal)
journalctl -u "$SVC" --no-pager -n 120 > "$EVID/journal_tail.txt" 2>&1 || true

# 2) /vsp5 10 tries (NEVER exit)
ok=0; bad=0
{
  for i in $(seq 1 10); do
    t0="$(date +%s%3N 2>/dev/null || true)"
    code="$(curl -sS --connect-timeout 1 --max-time 2 -o /dev/null -w "%{http_code}" "$BASE/vsp5" 2>/dev/null || echo 000)"
    t1="$(date +%s%3N 2>/dev/null || true)"
    dt="?"
    if [ -n "${t0:-}" ] && [ -n "${t1:-}" ] && [ "$t0" != "?" ] && [ "$t1" != "?" ]; then
      dt="$((t1-t0))ms"
    fi
    echo "try#$i code=$code time=$dt"
    if [ "$code" = "200" ]; then ok=$((ok+1)); else bad=$((bad+1)); fi
    sleep 0.2
  done
} | tee "$EVID/vsp5_10x.txt"

# 3) 5 tabs (non-fatal)
{
  for p in /vsp5 /runs /data_source /settings /rule_overrides; do
    code="$(curl -sS --connect-timeout 1 --max-time 3 -o /dev/null -w "%{http_code}" "$BASE$p" 2>/dev/null || echo 000)"
    echo "$p code=$code"
  done
} | tee "$EVID/tabs_5.txt"

# 4) verdict json (always exit 0)
python3 - <<PY > "$EVID/verdict.json" 2>/dev/null || true
import json, datetime
ok = ($ok == 10)
print(json.dumps({
  "ok": bool(ok),
  "ts": datetime.datetime.now().astimezone().isoformat(),
  "base": "$BASE",
  "service": "$SVC",
  "vsp5_ok_10": $ok,
  "vsp5_bad_10": $bad,
  "evidence_dir": "$EVID"
}, indent=2))
PY

echo "[DONE] evidence=$EVID (NO EXIT)"
exit 0
