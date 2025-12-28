#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
ok=0; fail=0

check200(){
  local path="$1"
  if curl -fsSI "${BASE}${path}" | head -n1 | grep -qi " 200 "; then
    echo "[OK] 200 ${path}"; ok=$((ok+1))
  else
    echo "[WARN] not 200 ${path}"; fail=$((fail+1))
  fi
}

echo "[BASE] $BASE"
check200 "/"
check200 "/vsp5"
check200 "/data_source"
check200 "/settings"
check200 "/rule_overrides"

echo "== RESULT =="
echo "OK=$ok WARN=$fail"
[ "$ok" -ge 3 ] || exit 3
