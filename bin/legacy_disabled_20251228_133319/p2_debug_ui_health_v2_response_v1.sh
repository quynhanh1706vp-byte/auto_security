#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
ERRLOG="${VSP_UI_ERRLOG:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log}"

tmp="$(mktemp -d /tmp/vsp_ui_health_dbg_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

lines_before=0
if [ -f "$ERRLOG" ]; then lines_before="$(wc -l <"$ERRLOG" 2>/dev/null || echo 0)"; fi

echo "== request =="
echo "URL=${BASE}/api/vsp/ui_health_v2"
echo "ERRLOG=$ERRLOG (lines_before=$lines_before)"
echo

# capture headers+body
curl -sS -D "$tmp/headers.txt" -o "$tmp/body.bin" --max-time 10 --connect-timeout 3 \
  "${BASE}/api/vsp/ui_health_v2" || true

code="$(awk 'NR==1{print $2}' "$tmp/headers.txt" 2>/dev/null || echo "")"
ctype="$(grep -i '^content-type:' "$tmp/headers.txt" | tail -n 1 | sed 's/\r$//' || true)"
len="$(stat -c%s "$tmp/body.bin" 2>/dev/null || wc -c <"$tmp/body.bin" 2>/dev/null || echo 0)"

echo "== response meta =="
echo "HTTP=${code:-UNKNOWN}"
echo "Content-Type=${ctype:-MISSING}"
echo "BodyLen=${len}"
echo

echo "== headers (top) =="
sed -n '1,30p' "$tmp/headers.txt" || true
echo

echo "== body preview (first 400 bytes) =="
python3 - "$tmp/body.bin" <<'PY' || true
import sys
p=sys.argv[1]
b=open(p,'rb').read(400)
# show printable preview
try:
    s=b.decode('utf-8','replace')
except Exception:
    s=str(b)
print(s)
PY
echo

echo "== json parse attempt =="
python3 - "$tmp/body.bin" <<'PY' || true
import json,sys
b=open(sys.argv[1],'rb').read()
try:
  s=b.decode('utf-8','strict')
except Exception:
  s=b.decode('utf-8','replace')
j=json.loads(s)
print("JSON_OK: ok=", j.get("ok"), "ready=", j.get("ready"), "marker=", j.get("marker"))
PY
echo

# dump new errlog lines
if [ -f "$ERRLOG" ]; then
  lines_after="$(wc -l <"$ERRLOG" 2>/dev/null || echo 0)"
  new_lines=$((lines_after - lines_before))
  echo "== errlog delta =="
  echo "lines_after=$lines_after new_lines=$new_lines"
  if [ "$new_lines" -gt 0 ]; then
    echo "== new errlog lines (tail) =="
    sed -n "$((lines_before+1)),\$p" "$ERRLOG" | tail -n 120 | sed 's/^/[ERRLOG+] /' || true
  else
    echo "[OK] no new errlog lines"
  fi
else
  echo "[WARN] ERRLOG not found"
fi

echo
echo "[OK] debug artifacts:"
echo "  $tmp/headers.txt"
echo "  $tmp/body.bin"
