#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

ok(){ echo "[OK] $*"; }
fail(){ echo "[FAIL] $*" >&2; exit 2; }

RID="$(curl -fsS "$BASE/api/vsp/top_findings_v2?limit=1" \
  | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("rid",""))')"
[ -n "$RID" ] || fail "RID empty from top_findings_v2"
ok "RID=$RID"

# Endpoints
curl -fsS "$BASE/api/vsp/top_findings_v2?limit=1" >/dev/null && ok "api top_findings_v2 200" || fail "api top_findings_v2 fail"
curl -fsS "$BASE/api/vsp/datasource?rid=$RID" >/dev/null && ok "api datasource rid 200" || fail "api datasource rid fail"

# Static JS exists
curl -fsS "$BASE/static/js/vsp_dashboard_main_v1.js" >/dev/null && ok "static dashboard_main_v1.js 200" || fail "missing dashboard_main_v1.js"

# Tabs5 markers
grep -q "VSP_P72B_LOAD_DASHBOARD_MAIN_V1" static/js/vsp_bundle_tabs5_v1.js \
  && ok "tabs5 has P72B loader" || fail "tabs5 missing P72B loader"
if grep -q "VSP_P68_FORCE_LOAD_LUXE_V1" static/js/vsp_bundle_tabs5_v1.js; then
  fail "tabs5 still contains P68 (should be removed)"
else
  ok "tabs5 no P68"
fi

# Luxe should NOT contain P71 forced fallback anymore
if grep -q "VSP_P71_FORCE_FALLBACK_RENDER_V1" static/js/vsp_dashboard_luxe_v1.js; then
  fail "luxe still has P71 (should be clean)"
else
  ok "luxe clean (no P71)"
fi

echo "[PASS] Dashboard commercial wiring looks good."
echo "Open: $BASE/vsp5?rid=$RID"
