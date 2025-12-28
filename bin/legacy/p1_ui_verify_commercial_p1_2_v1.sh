#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "[BASE] $BASE"

# 5 tabs
for P in / /vsp5 /data_source /settings /rule_overrides; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE$P" || true)"
  echo "[TAB] $P => $code"
  [ "$code" = "200" ] || { echo "[ERR] bad tab status for $P"; exit 2; }
done

# static assets should be served
for A in /static/css/vsp_dark_commercial_p1_2.css /static/js/vsp_ui_keepalive_p1_2.js; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE$A" || true)"
  echo "[ASSET] $A => $code"
  [ "$code" = "200" ] || { echo "[ERR] asset not served: $A"; exit 3; }
done

# marker present in vsp5 html
html="$(curl -sS "$BASE/vsp5" || true)"
echo "$html" | grep -q "VSP_UI_DARK_CSS_P1_2_INJECT" && echo "[OK] css inject marker" || echo "[WARN] css marker not found in /vsp5 html"
echo "$html" | grep -q "VSP_UI_KEEPALIVE_JS_P1_2_INJECT" && echo "[OK] js inject marker" || echo "[WARN] js marker not found in /vsp5 html"

echo "== RESULT: UI P1.2 verify PASS =="
