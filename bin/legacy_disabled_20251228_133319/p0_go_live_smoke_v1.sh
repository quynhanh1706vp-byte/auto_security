#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

ok(){ echo "[OK] $*"; }
fail(){ echo "[FAIL] $*" >&2; exit 1; }

echo "== [0] service status =="
command -v systemctl >/dev/null 2>&1 && systemctl is-active "$SVC" || true

echo "== [1] wait port =="
for i in $(seq 1 120); do
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1 && { ok "up: $BASE"; break; }
  sleep 0.25
  [ "$i" -eq 120 ] && fail "UI not reachable: $BASE"
done

echo "== [2] tabs 5 + c-suite 5 =="
for p in /vsp5 /runs /data_source /settings /rule_overrides /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 6 "$BASE$p?rid=$RID" || true)"
  echo "$p => $code"
  [ "$code" = "200" ] || [ "$code" = "302" ] || fail "bad code for $p: $code"
done

echo "== [3] api smoke + capture release headers =="
capture(){
  local name="$1" url="$2"
  echo "-- $name --"
  curl -fsSI --connect-timeout 1 --max-time 6 "$url" | egrep -i 'HTTP/|X-VSP-RELEASE|X-VSP-ASSET|Cache-Control|Content-Type' || true
  local code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 8 "$url" || true)"
  echo "code=$code url=$url"
  [ "$code" = "200" ] || fail "API FAIL: $url"
}

capture runs           "$BASE/api/vsp/runs?limit=1&offset=0"
capture findings_page  "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0"
capture top_findings   "$BASE/api/vsp/top_findings_v3c?rid=$RID&limit=50"
capture trend          "$BASE/api/vsp/trend_v1"
capture rule_overrides "$BASE/api/vsp/rule_overrides_v1"

echo "== [4] error log tail (best-effort) =="
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"
if [ -f "$ERRLOG" ]; then
  if tail -n 200 "$ERRLOG" | egrep -n "Traceback|SyntaxError|IndentationError|Exception" >/dev/null; then
    echo "[WARN] errlog has exceptions (tail):"
    tail -n 200 "$ERRLOG" | egrep -n "Traceback|SyntaxError|IndentationError|Exception" | tail -n 30
  else
    ok "errlog tail clean"
  fi
else
  echo "[INFO] errlog not found: $ERRLOG"
fi

ok "GO-LIVE SMOKE: GREEN ✅"
