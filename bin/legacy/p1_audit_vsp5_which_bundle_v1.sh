#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
tmp="$(mktemp -d /tmp/vsp5_audit_XXXXXX)"; trap 'rm -rf "$tmp"' EXIT

echo "== [1] fetch /vsp5 html =="
curl -fsS "$BASE/vsp5" -o "$tmp/vsp5.html"
echo "[OK] html_size=$(wc -c <"$tmp/vsp5.html")"

echo
echo "== [2] list JS src in /vsp5 =="
grep -oE 'src="[^"]+"' "$tmp/vsp5.html" \
  | sed 's/^src="//; s/"$//' \
  | grep -E '/static/js/' \
  | nl -ba

echo
echo "== [3] detect vsp_bundle_tabs5_v1.js in html =="
BUNDLE_URL="$(grep -oE 'src="[^"]*vsp_bundle_tabs5_v1\.js[^"]*"' "$tmp/vsp5.html" \
  | head -n 1 | sed 's/^src="//; s/"$//')"

if [ -z "${BUNDLE_URL:-}" ]; then
  echo "[WARN] /vsp5 does NOT include vsp_bundle_tabs5_v1.js"
  exit 0
fi

echo "[OK] bundle_url=$BUNDLE_URL"

echo
echo "== [4] fetch bundle and check marker =="
curl -fsS "$BASE$BUNDLE_URL" -o "$tmp/bundle.js"
grep -n "VSP_P1_DASH_MINICHARTS_V8B_KILLSWITCH_PIN_V1" "$tmp/bundle.js" || echo "[WARN] marker NOT found in fetched bundle"

echo
echo "== [5] sanity: show last 15 lines of bundle =="
tail -n 15 "$tmp/bundle.js" | nl -ba
