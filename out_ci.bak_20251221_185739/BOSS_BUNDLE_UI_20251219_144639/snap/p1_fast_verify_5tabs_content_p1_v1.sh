#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need grep

ok=0; warn=0
check200(){
  local p="$1"
  if curl -fsSI "${BASE}${p}" | head -n1 | grep -qi " 200 "; then
    echo "[OK] 200 ${p}"; ok=$((ok+1))
  else
    echo "[WARN] not 200 ${p}"; warn=$((warn+1))
  fi
}
checkMark(){
  local p="$1"
  if curl -fsS "${BASE}${p}" | grep -q "vsp_p1_page_boot_v1.js"; then
    echo "[OK] boot included ${p}"
  else
    echo "[WARN] boot missing ${p}"; warn=$((warn+1))
  fi
}

echo "[BASE] $BASE"
check200 "/"
check200 "/vsp5"
check200 "/data_source"
check200 "/settings"
check200 "/rule_overrides"

RID="$(curl -fsS "${BASE}/api/vsp/runs?limit=1" | jq -r '.items[0].run_id // empty')"
if [ -n "$RID" ]; then echo "[OK] latest RID=$RID"; else echo "[WARN] cannot read RID"; warn=$((warn+1)); fi

checkMark "/"
checkMark "/data_source"
checkMark "/settings"
checkMark "/rule_overrides"

echo "== RESULT =="
echo "OK=$ok WARN=$warn"
[ "$ok" -ge 5 ] || exit 3
