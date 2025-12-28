#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

DASH_JS="static/js/vsp_dashboard_luxe_v1.js"
BUNDLE_JS="static/js/vsp_bundle_tabs5_v1.js"

[ -f "$DASH_JS" ] || { echo "[ERR] missing $DASH_JS"; exit 2; }
[ -f "$BUNDLE_JS" ] || { echo "[ERR] missing $BUNDLE_JS"; exit 2; }

echo "== [1] JS syntax check (node --check) =="
if command -v node >/dev/null 2>&1; then
  node --check "$DASH_JS"
  node --check "$BUNDLE_JS"
  echo "[OK] node --check passed"
else
  echo "[WARN] node missing; skip syntax check"
fi

echo
echo "== [2] bump asset_v to avoid cache (if available) =="
if [ -x "bin/p1_set_asset_v_runtime_ts_v1.sh" ]; then
  bash bin/p1_set_asset_v_runtime_ts_v1.sh
else
  echo "[WARN] missing bin/p1_set_asset_v_runtime_ts_v1.sh (skip)"
fi

echo
echo "== [3] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
else
  echo "[WARN] systemctl missing; restart manually"
fi

echo
echo "== [4] quick verify =="
for p in /vsp5 /settings /rule_overrides; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$p" || true)"
  echo "$p => $code"
done

echo
echo "== [5] show KPI degraded source =="
curl -fsS "$BASE/api/vsp/dash_kpis" | head -c 200; echo
curl -fsS "$BASE/api/vsp/dash_charts" | head -c 200; echo

echo
echo "[OK] Open /vsp5 now: should see KPI Degraded banner."
echo "[OK] Open /settings: should see Tool Coverage & Policy panel."
echo "[OK] Open /rule_overrides: should see Save/Reload bar (but save contract fixed in next script below)."
