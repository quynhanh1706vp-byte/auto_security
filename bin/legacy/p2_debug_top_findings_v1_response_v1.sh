#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
ERRLOG="${VSP_UI_ERRLOG:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log}"

tmp="$(mktemp -d /tmp/vsp_topfind_dbg_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

lines_before=0
if [ -f "$ERRLOG" ]; then lines_before="$(wc -l <"$ERRLOG" 2>/dev/null || echo 0)"; fi

URL="${BASE}/api/vsp/top_findings_v1?limit=1"
echo "== request =="
echo "URL=$URL"
echo "ERRLOG=$ERRLOG (lines_before=$lines_before)"

# IMPORTANT: do NOT use -f here; we need body even on 4xx/5xx
curl -sS -D "$tmp/headers.txt" -o "$tmp/body.bin" "$URL" || true

echo
echo "== response meta =="
head -n 1 "$tmp/headers.txt" | sed 's/^/STATUS_LINE= /'
grep -i '^Content-Type:' "$tmp/headers.txt" | head -n 1 || true
grep -i '^X-VSP-TOPFIND-RUNID-FIX:' "$tmp/headers.txt" || true
echo "BodyLen=$(wc -c <"$tmp/body.bin" | tr -d ' ')"

echo
echo "== body preview (first 300 bytes) =="
head -c 300 "$tmp/body.bin" | sed 's/^/BODY: /'
echo

echo
echo "== json parse attempt =="
python3 - <<'PY' "$tmp/body.bin"
import json,sys
p=sys.argv[1]
b=open(p,'rb').read()
try:
    j=json.loads(b.decode('utf-8',errors='replace'))
    print("JSON_OK: ok=", j.get("ok"), "run_id=", j.get("run_id"), "total=", j.get("total"), "marker=", j.get("marker"))
except Exception as e:
    print("JSON_FAIL:", type(e).__name__, e)
PY

echo
echo "== errlog delta =="
lines_after=0
if [ -f "$ERRLOG" ]; then lines_after="$(wc -l <"$ERRLOG" 2>/dev/null || echo 0)"; fi
echo "lines_after=$lines_after new_lines=$((lines_after-lines_before))"
if [ "$lines_after" -gt "$lines_before" ]; then
  echo "== new errlog lines (tail) =="
  tail -n 80 "$ERRLOG" | sed 's/^/[ERRLOG+] /'
fi

echo
echo "[OK] debug artifacts:"
echo "  $tmp/headers.txt"
echo "  $tmp/body.bin"
