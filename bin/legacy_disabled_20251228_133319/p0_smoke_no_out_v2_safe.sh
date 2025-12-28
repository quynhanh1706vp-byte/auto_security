#!/usr/bin/env bash
set -u
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="/tmp/vsp_smoke_safe_$$"
mkdir -p "$OUT"
TO="$(command -v timeout || true)"

fetch(){
  local path="$1"
  local f="$OUT/$(echo "$path" | tr '/?' '__').html"
  echo "== FETCH $path =="
  if [ -n "$TO" ]; then
    $TO 5s curl -fsS --connect-timeout 1 --max-time 4 --range 0-120000 "$BASE$path" -o "$f" \
      && echo "[OK] saved=$f bytes=$(wc -c <"$f")" \
      || { echo "[FAIL] fetch $path"; return 1; }
  else
    curl -fsS --connect-timeout 1 --max-time 4 --range 0-120000 "$BASE$path" -o "$f" \
      && echo "[OK] saved=$f bytes=$(wc -c <"$f")" \
      || { echo "[FAIL] fetch $path"; return 1; }
  fi
}

probe(){
  local name="$1" f="$2"
  echo "### $name"
  echo "-- cio shell tags --"
  grep -n "vsp_cio_shell_v1\.css\|vsp_cio_shell_apply_v1\.js" "$f" | head -n 10 || true
  echo "-- luxe tag --"
  grep -n "vsp_dashboard_luxe_v1\.js" "$f" | head -n 10 || true
}

pass=0; fail=0
echo "== HEALTH =="
if curl -fsS --connect-timeout 1 --max-time 3 "$BASE/api/vsp/rid_latest" >/dev/null 2>&1; then
  echo "[OK] API reachable"
else
  echo "[FAIL] API not reachable"
  exit 2
fi

declare -a pages=("/vsp5" "/runs" "/data_source" "/settings" "/rule_overrides")
for p in "${pages[@]}"; do
  fetch "$p" || { fail=$((fail+1)); continue; }
  pass=$((pass+1))
done

echo
echo "== PROBE TAGS =="
probe "/vsp5" "$OUT/_vsp5.html"
probe "/runs" "$OUT/_runs.html"
probe "/data_source" "$OUT/_data_source.html"
probe "/settings" "$OUT/_settings.html"
probe "/rule_overrides" "$OUT/_rule_overrides.html"

echo
echo "== EXPECTATIONS =="
echo "1) /vsp5: MUST have CIO css+js AND luxe js"
echo "2) others: MUST have CIO css+js AND MUST NOT have luxe js"
echo
echo "[DONE] pass=$pass fail=$fail out=$OUT"
exit 0
