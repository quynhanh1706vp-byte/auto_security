#!/usr/bin/env bash
# CIO smoke: warmup -> measure -> gate latency
# Gate:
#   findings_page_v3 max <= 5.0s (after warmup)  [fail if >5]
#   warn if max > 2.0s
set -u
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "[ERR] Do NOT source. Run: bash ${BASH_SOURCE[0]}"
  return 2
fi
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

FAIL_GT="${FAIL_GT:-5.0}"
WARN_GT="${WARN_GT:-2.0}"

echo "BASE=$BASE RID=$RID SVC=$SVC FAIL_GT=${FAIL_GT}s WARN_GT=${WARN_GT}s"

echo "== [0] service =="
command -v systemctl >/dev/null 2>&1 && systemctl is-active "$SVC" || true

echo "== [1] warmup workers =="
RID="$RID" N="${N:-12}" bash /home/test/Data/SECURITY_BUNDLE/ui/bin/p0_warmup_findings_workers_v1.sh >/dev/null || true

echo "== [2] measure findings_page_v3 (5 samples) =="
URL="$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0"
tmp="$(mktemp /tmp/vsp_findings_time_XXXX.txt)"
trap 'rm -f "$tmp"' EXIT

for i in 1 2 3 4 5; do
  t="$(curl -sS -o /dev/null -w "%{time_total}" --connect-timeout 1 --max-time 20 "$URL" || echo 99)"
  echo "$t" | tee -a "$tmp" >/dev/null
  echo "sample#$i t=${t}s"
done

max="$(awk 'BEGIN{m=0} {if($1+0>m)m=$1+0} END{printf "%.3f",m}' "$tmp")"
echo "[INFO] findings_page_v3 max=${max}s"

awk -v m="$max" -v f="$FAIL_GT" 'BEGIN{exit ! (m>f)}' && { echo "[FAIL] findings_page_v3 too slow: max=${max}s > ${FAIL_GT}s"; exit 2; } || true
awk -v m="$max" -v w="$WARN_GT" 'BEGIN{exit ! (m>w)}' && echo "[WARN] findings_page_v3 max=${max}s > ${WARN_GT}s" || echo "[OK] findings_page_v3 latency OK"

echo "== [3] run existing smoke (functional) =="
RID="$RID" bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_ops_safe_v3.sh smoke

echo "[OK] CIO SMOKE PASS ✅"
