#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need sort; need sed; need awk; need head; need python3

if [ -z "$RID" ]; then
  RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
fi
echo "[INFO] BASE=$BASE"
echo "[INFO] RID=$RID"

tmp="$(mktemp -d /tmp/vsp_js_probe_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

HTML="$tmp/vsp5.html"
curl -fsS "$BASE/vsp5?rid=$RID" -o "$HTML"

echo "== [A] JS referenced by /vsp5 =="
grep -oE '/static/js/[^"]+\.js(\?v=[^"]+)?' "$HTML" | sort -u | tee "$tmp/js.list" || true

echo
echo "== [B] Extract /api/vsp endpoints inside those JS (best-effort) =="
: > "$tmp/apis.txt"
while read -r js; do
  [ -n "$js" ] || continue
  f="$tmp/$(echo "$js" | tr '/?&=' '____').js"
  curl -fsS "$BASE$js" -o "$f" || continue
  # catch both "/api/vsp/..." and "api/vsp/..." and full "http://..../api/vsp/..."
  grep -oE 'https?://[^"'\'' ]+/api/vsp/[a-zA-Z0-9_]+|/api/vsp/[a-zA-Z0-9_]+|api/vsp/[a-zA-Z0-9_]+' "$f" \
    | sed -E 's#https?://[^/]+##' \
    | sed -E 's#^api#/#' \
    >> "$tmp/apis.txt" || true
done < "$tmp/js.list"

sort -u "$tmp/apis.txt" | head -n 120 | sed 's/^/  /'
echo
echo "[OK] saved: $tmp (js.list + apis.txt)"
