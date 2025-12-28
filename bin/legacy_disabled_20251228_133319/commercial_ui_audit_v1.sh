#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need sed; need awk; need head; need sort; need mktemp; need mkdir; need date

tmp="$(mktemp -d /tmp/vsp_ui_audit_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

tabs=(/vsp5 /runs /releases /data_source /settings /rule_overrides)

echo "== [A] fetch HTML per tab + extract JS =="
: > "$tmp/js_urls.txt"
for t in "${tabs[@]}"; do
  echo "--- TAB $t"
  html="$tmp/tab$(echo "$t" | tr '/' '_').html"
  curl -fsS "$BASE$t" -o "$html"
  grep -oE '/static/js/[^"]+\.js\?v=[0-9]+' "$html" | sort -u | tee -a "$tmp/js_urls.txt" | head -n 200 || true
done
sort -u "$tmp/js_urls.txt" -o "$tmp/js_urls.txt"

echo
echo "== [B] download JS assets =="
mkdir -p "$tmp/js"
while read -r u; do
  [ -n "${u:-}" ] || continue
  fn="$tmp/js/$(echo "$u" | sed 's#/#_#g;s#[?=&]#_#g')"
  curl -fsS "$BASE$u" -o "$fn" || echo "[WARN] cannot fetch $u" >&2
done < "$tmp/js_urls.txt"

scan(){
  local pat="$1" label="$2"
  echo
  echo "== [SCAN] $label =="
  if grep -RIn -E "$pat" "$tmp/js" | head -n 120; then
    true
  else
    echo "(none)"
  fi
}

scan 'run_file_allow\?' 'FORBIDDEN: FE calls run_file_allow (should be tab-scoped API)'
scan 'findings_unified\.json|reports/findings_unified\.json' 'FORBIDDEN: FE mentions internal files'
scan '/home/test/Data/|/home/test/|/SECURITY_BUNDLE/' 'FORBIDDEN: internal filesystem path leaked'
scan 'UNIFIED FROM|debug|dev only|__vsp' 'DEBUG strings leaked (review)'

scan '/api/vsp/[^" ]+_v1|/api/vsp/[^" ]+_v2' 'LEGACY API usage (prefer stateless v3 per tab)'
scan '/api/vsp/rid_latest|/api/vsp/runs\?|/api/vsp/dash_kpis|/api/vsp/run_file_allow' 'High-churn endpoints (check spam/caching)'

scan 'N/A' 'CIO UX: N/A present in UI rendering (should be 0/— + tooltip)'
scan 'not available' 'CIO UX: "not available" strings present'

echo
echo "[OK] Audit workspace: $tmp"
echo "[TIP] Keep it: cp -a $tmp /home/test/Data/SECURITY_BUNDLE/ui/out_audit_$(date +%Y%m%d_%H%M%S)"
