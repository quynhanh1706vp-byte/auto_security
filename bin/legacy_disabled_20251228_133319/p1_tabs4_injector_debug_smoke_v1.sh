#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

pages=(/runs /runs_reports /settings /data_source /rule_overrides)

echo "== [A] HEAD check (status + content-type) =="
for p in "${pages[@]}"; do
  echo "-- $p --"
  curl -sS -I "$BASE$p" | sed -n '1,12p'
done

echo
echo "== [B] BODY check (body has </body>? has autorid marker? size) =="
for p in "${pages[@]}"; do
  echo "-- $p --"
  BODY="$(curl -sS "$BASE$p")"
  echo "size=$(printf "%s" "$BODY" | wc -c)"
  printf "%s" "$BODY" | grep -q "</body>" && echo "[OK] has </body>" || echo "[WARN] missing </body>"
  printf "%s" "$BODY" | grep -q "VSP_P1_TABS4_AUTORID_NODASH_V1" && echo "[OK] has inject marker" || echo "[WARN] missing inject marker"
  printf "%s" "$BODY" | grep -q "vsp_tabs4_autorid_v1.js" && echo "[OK] has autorid src" || echo "[WARN] missing autorid src"
  # show first hit lines around body end
  echo "--- tail 12 lines (minified safe) ---"
  printf "%s" "$BODY" | tail -n 12
done
