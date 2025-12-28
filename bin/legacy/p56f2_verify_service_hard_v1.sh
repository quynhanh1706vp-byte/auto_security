#!/usr/bin/env bash
set -u
cd /home/test/Data/SECURITY_BUNDLE/ui 2>/dev/null || exit 0

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56f2_verify_${TS}"; mkdir -p "$EVID"

echo "== [P56F2] BASE=$BASE SVC=$SVC ==" | tee "$EVID/summary.txt"

# 1) systemd status (non-fatal)
{
  echo "== systemctl is-active ==";
  systemctl is-active "$SVC" 2>&1 || true
  echo "== systemctl status (head) ==";
  systemctl status "$SVC" --no-pager 2>&1 | head -n 60 || true
} | tee "$EVID/systemd.txt" >/dev/null

# 2) port listen
{
  echo "== ss -lntp | grep 8910 ==";
  ss -lntp 2>/dev/null | grep -E '(:8910|8910)' || true
} | tee "$EVID/port.txt" >/dev/null

# 3) curl warm loop
ok=0
for i in $(seq 1 20); do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$BASE/vsp5" || echo 000)"
  echo "try#$i /vsp5 code=$code" | tee -a "$EVID/curl.txt"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 1
done

# 4) tab checks
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 3 "$BASE$p" || echo 000)"
  echo "$p code=$code" | tee -a "$EVID/curl_tabs.txt"
done

# 5) journal tail
{
  echo "== journalctl tail ==";
  journalctl -u "$SVC" --no-pager -n 120 2>&1 || true
} | tee "$EVID/journal_tail.txt" >/dev/null

if [ "$ok" != "1" ]; then
  echo "[FAIL] /vsp5 did not reach 200 within 20s. Evidence=$EVID"
else
  echo "[PASS] Service reachable. Evidence=$EVID"
fi
exit 0
