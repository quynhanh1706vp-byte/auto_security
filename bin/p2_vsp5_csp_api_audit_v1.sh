#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need sort; need head; need mktemp

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin)["rid"])')"
echo "[INFO] BASE=$BASE"
echo "[INFO] RID=$RID"

tmp="$(mktemp -d /tmp/vsp5_csp_api_XXXXXX)"
trap 'echo "[INFO] kept: '"$tmp"'"' EXIT

URL="$BASE/vsp5?rid=$RID"
echo "== [1] Fetch /vsp5?rid and show CSP headers =="
curl -fsS -D "$tmp/vsp5.hdr" -o "$tmp/vsp5.html" "$URL" || true
echo "[INFO] html_bytes=$(wc -c < "$tmp/vsp5.html" 2>/dev/null || echo 0)"

echo "-- Content-Security-Policy headers (if any) --"
grep -i '^content-security-policy:' "$tmp/vsp5.hdr" || echo "[AMBER] no CSP header found"

python3 - "$tmp/vsp5.hdr" <<'PY'
import re,sys
hdr=open(sys.argv[1],'r',encoding='utf-8',errors='replace').read()
m=re.search(r'(?im)^content-security-policy:\s*(.+)$', hdr)
if not m:
  print("[INFO] CSP: (none)")
  raise SystemExit(0)
csp=m.group(1).strip()
print("[INFO] CSP_LEN=", len(csp))
# quick heuristics
def has_self(directive):
  mm=re.search(r'(?i)(?:^|;\s*)'+re.escape(directive)+r'\s+([^;]+)', csp)
  if not mm: return None
  val=mm.group(1)
  return ("'self'" in val), val[:180]
for d in ["script-src","style-src","default-src"]:
  r=has_self(d)
  if r is None:
    print(f"[AMBER] {d}: missing")
  else:
    ok,val=r
    print(f"[CHECK] {d}: has 'self'={ok} ; sample={val}")
PY

echo
echo "== [2] Extract JS from HTML and grep all /api/vsp/* endpoints inside those JS =="
grep -oE '/static/js/[^"]+\.js(\?v=[0-9]+)?' "$tmp/vsp5.html" | sort -u > "$tmp/js.list" || true
if [ ! -s "$tmp/js.list" ]; then
  echo "[RED] no JS referenced in HTML => explains blank if dashboard is JS-rendered"
  exit 0
fi

echo "[INFO] JS referenced:"
sed 's/^/  /' "$tmp/js.list" | head -n 50

> "$tmp/api.list"
while IFS= read -r p; do
  f="$tmp/$(echo "$p" | sed 's#[/?=&]#_#g')"
  curl -fsS -o "$f" "$BASE$p" || continue
  # grab /api/vsp/... occurrences
  grep -oE '/api/vsp/[A-Za-z0-9_./-]+(\?[A-Za-z0-9_./%=&-]+)?' "$f" >> "$tmp/api.list" || true
done < "$tmp/js.list"

sort -u "$tmp/api.list" > "$tmp/api.uniq" || true
echo "[INFO] API refs found in JS: $(wc -l < "$tmp/api.uniq" 2>/dev/null || echo 0)"
sed 's/^/  /' "$tmp/api.uniq" | head -n 120

echo
echo "== [3] Call each API (raw + maybe append rid) and report status/ok =="
call_one(){
  local path="$1"
  local full="$BASE$path"
  local h="$tmp/hdr.txt"
  local b="$tmp/body.txt"
  local code ct okv
  code="$(curl -sS -D "$h" -o "$b" -w "%{http_code}" "$full" || true)"
  ct="$(grep -i '^content-type:' "$h" | head -n1 | sed 's/\r//g')"
  printf "  %s  %s  %s\n" "${code:-000}" "$path" "${ct:-}"
  if [ "${code:-000}" != "200" ]; then
    echo "    [BODY_SNIFF] $(head -c 200 "$b" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
    return 0
  fi
  if echo "$ct" | grep -qi 'application/json'; then
    okv="$(python3 - <<PY 2>/dev/null
import json,sys
try:
  j=json.load(open("$b","r",encoding="utf-8",errors="replace"))
  print(j.get("ok", "NO_OK_FIELD"))
except Exception as e:
  print("JSON_PARSE_ERR")
PY
)"
    echo "    [JSON ok] $okv"
    if [ "$okv" = "false" ] || [ "$okv" = "JSON_PARSE_ERR" ]; then
      echo "    [JSON_SNIFF] $(head -c 260 "$b" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
    fi
  fi
}

while IFS= read -r ep; do
  [ -z "$ep" ] && continue
  # call as-is
  call_one "$ep"
  # if not already has rid= and looks like it might need rid, also try append rid
  if ! echo "$ep" | grep -q 'rid='; then
    if echo "$ep" | grep -q '?'; then
      call_one "${ep}&rid=${RID}"
    else
      call_one "${ep}?rid=${RID}"
    fi
  fi
done < "$tmp/api.uniq"

echo
echo "[NEXT] If CSP script-src lacks 'self' OR any API returns non-200/ok=false => that’s the reason dashboard stays blank."
