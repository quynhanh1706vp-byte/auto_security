#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="/tmp/vsp_smoke_no_out_$$"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need head; need wc

# prefer timeout, but if missing just run without it
TO="$(command -v timeout || true)"

fetch(){
  local path="$1"
  local f="$OUT/$(echo "$path" | tr '/?' '__').html"
  echo "== FETCH $path =="
  if [ -n "$TO" ]; then
    # 80KB max + 4s hard cap
    $TO 4s curl -fsS --connect-timeout 1 --max-time 3 --range 0-80000 "$BASE$path" -o "$f" \
      || { echo "[WARN] fetch failed: $path"; return 1; }
  else
    curl -fsS --connect-timeout 1 --max-time 3 --range 0-80000 "$BASE$path" -o "$f" \
      || { echo "[WARN] fetch failed: $path"; return 1; }
  fi
  echo "[OK] saved=$f bytes=$(wc -c <"$f")"
  return 0
}

probe(){
  local path="$1"
  local f="$OUT/$(echo "$path" | tr '/?' '__').html"
  [ -s "$f" ] || { echo "[SKIP] no file for $path"; return 0; }

  echo "-- tags in $path --"
  # only print very few lines to avoid terminal "out"
  grep -nE 'vsp_dashboard_luxe_v1\.js|vsp_cio_shell_v1\.css|vsp_cio_shell_apply_v1\.js' "$f" \
    | head -n 20 || true
}

# 0) quick health (no body)
echo "== HEALTH =="
curl -fsS --connect-timeout 1 --max-time 2 -o /dev/null -w "vsp5_http=%{http_code}\n" "$BASE/vsp5" || true

# 1) fetch minimal HTML heads
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  fetch "$p" || true
done

# 2) probe tags
echo
echo "== PROBE TAGS =="
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "### $p"
  probe "$p"
done

echo
echo "== EXPECTATIONS =="
echo "1) /vsp5: MUST contain cio_shell css+js AND luxe js"
echo "2) others: MUST contain cio_shell css+js AND MUST NOT contain luxe js"
echo
echo "[DONE] files at: $OUT"
