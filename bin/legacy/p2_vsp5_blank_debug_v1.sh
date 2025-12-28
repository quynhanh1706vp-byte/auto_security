#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need head; need sort; need tail

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin)["rid"])')"
echo "[INFO] RID=$RID"

tmp="$(mktemp -d /tmp/vsp5_dbg_XXXXXX)"
trap 'echo "[INFO] kept: '"$tmp"'"' EXIT

u1="$BASE/vsp5"
u2="$BASE/vsp5?rid=$RID"

echo "== [1] Fetch HTML =="
curl -fsS -D "$tmp/h1.hdr" -o "$tmp/vsp5.html" "$u1" || true
curl -fsS -D "$tmp/h2.hdr" -o "$tmp/vsp5_rid.html" "$u2" || true
echo "[INFO] /vsp5 bytes:     $(wc -c < "$tmp/vsp5.html" 2>/dev/null || echo 0)"
echo "[INFO] /vsp5?rid bytes: $(wc -c < "$tmp/vsp5_rid.html" 2>/dev/null || echo 0)"

echo "== [2] Anchor checks =="
for f in vsp5.html vsp5_rid.html; do
  echo "-- $f"
  if grep -q 'id="vsp-dashboard-main"' "$tmp/$f"; then
    echo "  [OK] has #vsp-dashboard-main"
  else
    echo "  [RED] MISSING #vsp-dashboard-main"
  fi
  if grep -qi '<title' "$tmp/$f"; then echo "  [OK] has <title>"; else echo "  [AMBER] missing <title>"; fi
done

echo "== [3] JS list (from HTML) =="
for f in vsp5.html vsp5_rid.html; do
  echo "-- $f"
  grep -oE '/static/js/[^"]+\.js(\?v=[0-9]+)?' "$tmp/$f" | sort -u | sed 's/^/  /' || true
done

echo "== [4] Check JS status (HEAD) =="
js_all="$( (grep -oE '/static/js/[^"]+\.js(\?v=[0-9]+)?' "$tmp/vsp5.html" || true;
            grep -oE '/static/js/[^"]+\.js(\?v=[0-9]+)?' "$tmp/vsp5_rid.html" || true) | sort -u )"
if [ -z "${js_all// /}" ]; then
  echo "[AMBER] no JS referenced in HTML (could explain blank if UI is JS-rendered)"
else
  while IFS= read -r p; do
    code="$(curl -s -o /dev/null -w "%{http_code}" -I "$BASE$p" || true)"
    echo "  $code  $p"
  done <<< "$js_all"
fi

echo "== [5] Look for obvious inline redirect / CSP / errors in HTML =="
for f in vsp5.html vsp5_rid.html; do
  echo "-- $f (sniff)"
  egrep -n 'Content-Security-Policy|meta http-equiv|window\.location|location\.|__vsp|error|Exception' "$tmp/$f" | head -n 80 || true
done

echo "== [6] Tail server error log around /vsp5 =="
LOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"
if [ -f "$LOG" ]; then
  tail -n 200 "$LOG" | egrep -n 'GET /vsp5|Traceback|Exception|ERROR|500|CSP|blocked|static/js' || true
else
  echo "[AMBER] missing log: $LOG"
fi

echo
echo "[NEXT] If /vsp5 ok but /vsp5?rid missing anchor or JS 404 => route/template split OR stale cache."
