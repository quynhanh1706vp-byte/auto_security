#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need head

OK=0; WARN=0; ERR=0
ok(){ echo "[OK] $*"; OK=$((OK+1)); }
warn(){ echo "[WARN] $*"; WARN=$((WARN+1)); }
err(){ echo "[ERR] $*"; ERR=$((ERR+1)); }

pages=(/runs /settings /data_source /rule_overrides)

echo "== [1] 4 tabs: HTTP 200 + text/html =="
for p in "${pages[@]}"; do
  H="$(curl -sS -I "$BASE$p" || true)"
  code="$(printf "%s" "$H" | head -n1 | awk '{print $2}')"
  ct="$(printf "%s" "$H" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}' | tail -n1)"
  if [ "$code" = "200" ] && echo "$ct" | grep -qi 'text/html'; then
    ok "$p code=$code ct=$ct"
  else
    err "$p code=$code ct=$ct"
  fi
done

echo
echo "== [2] Extract JS urls from each page; ensure /static/js/*.js has ?v=<number> =="
for p in "${pages[@]}"; do
  html="$(curl -sS "$BASE$p" || true)"
  echo "-- $p --"
  # list js
  js="$(printf "%s" "$html" | grep -oE 'src=[\"\x27]/static/js/[^\"\x27]+\.js(\?[^\"\x27]+)?[\"\x27]' \
    | sed -E 's/^src=[\"\x27]//; s/[\"\x27]$//' | head -n 50)"
  if [ -z "$js" ]; then
    warn "$p: no /static/js/*.js found"
    continue
  fi
  printf "%s\n" "$js" | head -n 20

  # check v param
  bad="$(printf "%s\n" "$js" | grep -E '/static/js/.*\.js($|[?](?!.*\bv=)[^#]*$)' || true)"
  if [ -n "$bad" ]; then
    err "$p: JS missing v= : $(printf "%s" "$bad" | head -n 3 | tr '\n' ' ')"
  else
    ok "$p: all JS has v="
  fi
done

echo
echo "== [3] MIME check: vsp_data_source_lazy_v1.js must be application/javascript =="
# discover actual URL used on /data_source
ds_html="$(curl -sS "$BASE/data_source" || true)"
ds_js="$(printf "%s" "$ds_html" | grep -oE '/static/js/vsp_data_source_lazy_v1\.js(\?[^\"\x27]+)?' | head -n 1 || true)"
if [ -z "$ds_js" ]; then
  warn "Could not find vsp_data_source_lazy_v1.js on /data_source (maybe bundled)."
else
  H="$(curl -sS -I "$BASE$ds_js" || true)"
  ct="$(printf "%s" "$H" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}' | tail -n1)"
  if echo "$ct" | grep -qi 'application/javascript'; then
    ok "$ds_js ct=$ct"
  else
    err "$ds_js ct=$ct (expected application/javascript)"
    echo "[HINT] If ct is application/json, hard-reload + Disable cache; else page might reference a different JS URL."
  fi
fi

echo
echo "== [4] run_file_allow contract: must return HTTP 200 + JSON parseable + ok boolean =="
RID="${RID_SMOKE:-__NO_SUCH_RID__}"
PATH_BAD="${PATH_SMOKE:-../etc/passwd}"
resp="$(curl -sS -w '\n__HTTP__%{http_code}\n' "$BASE/api/vsp/run_file_allow?rid=$RID&path=$PATH_BAD" || true)"
http="$(printf "%s" "$resp" | awk -F'__HTTP__' 'NF>1{print $2}' | tr -d '\r' | tail -n1)"
body="$(printf "%s" "$resp" | sed '/^__HTTP__/,$d')"

if [ "$http" = "200" ]; then ok "run_file_allow http=200"; else err "run_file_allow http=$http"; fi

python3 - <<PY
import json,sys
s = sys.stdin.read()
try:
    j = json.loads(s)
except Exception as e:
    print("[ERR] JSON parse failed:", e)
    sys.exit(3)
if "ok" not in j:
    print("[ERR] missing key: ok")
    sys.exit(4)
print("[OK] ok=", j.get("ok"), "keys=", sorted(list(j.keys()))[:12])
# recommended contract fields
missing = [k for k in ("http","err","rid","path") if k not in j]
if missing:
    print("[WARN] missing recommended fields:", missing)
PY
<<<"$body" && ok "run_file_allow JSON ok" || err "run_file_allow JSON bad/contract"

echo
echo "== SUMMARY =="
echo "OK=$OK WARN=$WARN ERR=$ERR"
[ "$ERR" -eq 0 ]
