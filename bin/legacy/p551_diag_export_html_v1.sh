#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-}"
latest="$(ls -1dt out_ci/p550_* 2>/dev/null | head -n1 || true)"
[ -n "$latest" ] || { echo "[FAIL] no out_ci/p550_* found"; exit 2; }

if [ -z "$RID" ]; then
  if [ -f "$latest/RID.txt" ]; then RID="$(cat "$latest/RID.txt")"; fi
fi
[ -n "$RID" ] || { echo "[FAIL] cannot determine RID (set RID=...)"; exit 2; }

echo "== [P551] BASE=$BASE RID=$RID latest=$latest =="

html="$(ls -1 "$latest"/report_*.html 2>/dev/null | head -n1 || true)"
hdr="${html}.hdr"
urlf="${html}.url"

echo "== [A] what P550 downloaded =="
if [ -n "$html" ] && [ -f "$html" ]; then
  echo "[FILE] $html ($(wc -c <"$html") bytes)"
  [ -f "$urlf" ] && echo "[URL ] $(cat "$urlf")" || true
  if [ -f "$hdr" ]; then
    echo "--- headers ---"
    sed -n '1,80p' "$hdr"
  else
    echo "[WARN] no hdr file: $hdr"
  fi
  echo "--- body (printable) ---"
  cat "$html" || true
  echo
  echo "--- body (hexdump first 120 bytes) ---"
  python3 - <<'PY' "$html"
import sys,binascii
b=open(sys.argv[1],'rb').read(120)
print(binascii.hexlify(b).decode())
PY
else
  echo "[WARN] no report_*.html found in $latest"
fi

echo
echo "== [B] probe candidate HTML endpoints =="
cands=(
  "$BASE/api/vsp/export_html_v1?rid=$RID"
  "$BASE/api/vsp/report_html_v1?rid=$RID"
  "$BASE/api/vsp/export_report_v1?rid=$RID&fmt=html"
  "$BASE/api/vsp/report_export_v1?rid=$RID&fmt=html"
)

ok_url=""
for u in "${cands[@]}"; do
  out="$latest/probe_$(echo "$u" | sed 's#[^A-Za-z0-9]#_#g').html"
  hh="${out}.hdr"
  # -L to follow redirects (302)
  code="$(curl -sS -L -D "$hh" -o "$out" -w "%{http_code}" --connect-timeout 2 --max-time 20 "$u" || true)"
  sz="$(wc -c <"$out" 2>/dev/null || echo 0)"
  ct="$(awk 'BEGIN{IGNORECASE=1} /^Content-Type:/{print $0}' "$hh" | tail -n1 || true)"
  has_html="NO"
  if grep -qiE "<html|<!doctype" "$out" 2>/dev/null; then has_html="YES"; fi
  printf "URL=%s\n  code=%s size=%s has_html=%s %s\n" "$u" "$code" "$sz" "$has_html" "$ct"
  if [ "$code" = "200" ] && [ "$sz" -ge 800 ] && [ "$has_html" = "YES" ] && [ -z "$ok_url" ]; then
    ok_url="$u"
  fi
done

echo
if [ -n "$ok_url" ]; then
  echo "[OK] Found working HTML export endpoint:"
  echo "  $ok_url"
  exit 0
fi

echo "[FAIL] None of candidate endpoints returned real HTML (>=800B + <html>)."
echo "Next: patch the backend export route to return actual HTML content (not 'ok'/'path'/'json')."
exit 2
