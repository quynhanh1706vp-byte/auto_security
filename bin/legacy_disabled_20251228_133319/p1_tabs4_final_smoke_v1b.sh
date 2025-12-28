#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need head; need mktemp

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
echo "== [2] JS src in each page: must have v=<digits> and must NOT contain {{ asset_v }} =="
for p in "${pages[@]}"; do
  html="$(curl -sS "$BASE$p" || true)"
  echo "-- $p --"
  js="$(printf "%s" "$html" \
    | grep -oE 'src=("[^"]+"|'\''[^'\'']+'\'')' \
    | sed -E 's/^src=//; s/^"|"$//g; s/^\x27|\x27$//g' \
    | grep -E '^/static/js/.*\.js' \
    | head -n 80 || true)"
  if [ -z "$js" ]; then
    warn "$p: no /static/js/*.js found"
    continue
  fi
  printf "%s\n" "$js" | head -n 20

  bad1="$(printf "%s\n" "$js" | grep -E 'v=\{\{|\{\{|asset_v' || true)"
  bad2="$(printf "%s\n" "$js" | grep -Ev '(\?|&)v=[0-9]+' || true)"

  if [ -n "$bad1" ]; then
    err "$p: template token still present in JS URL: $(printf "%s" "$bad1" | head -n 2 | tr '\n' ' ')"
  else
    ok "$p: no template tokens"
  fi
  if [ -n "$bad2" ]; then
    err "$p: JS missing numeric v=: $(printf "%s" "$bad2" | head -n 2 | tr '\n' ' ')"
  else
    ok "$p: all JS has numeric v="
  fi
done

echo
echo "== [3] MIME check: vsp_data_source_lazy_v1.js must be application/javascript =="
ds_html="$(curl -sS "$BASE/data_source" || true)"
ds_js="$(printf "%s" "$ds_html" | grep -oE '/static/js/vsp_data_source_lazy_v1\.js(\?[^"'\'' ]+)?' | head -n 1 || true)"
if [ -z "$ds_js" ]; then
  warn "Could not find vsp_data_source_lazy_v1.js on /data_source"
else
  H="$(curl -sS -I "$BASE$ds_js" || true)"
  ct="$(printf "%s" "$H" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}' | tail -n1)"
  if echo "$ct" | grep -qi 'application/javascript'; then
    ok "$ds_js ct=$ct"
  else
    err "$ds_js ct=$ct"
  fi
fi

echo
echo "== [4] run_file_allow contract: HTTP 200 + JSON parseable + ok boolean =="
RID="${RID_SMOKE:-__NO_SUCH_RID__}"
PATH_BAD="${PATH_SMOKE:-../etc/passwd}"
tmp="$(mktemp)"
http="$(curl -sS -o "$tmp" -w '%{http_code}' "$BASE/api/vsp/run_file_allow?rid=$RID&path=$PATH_BAD" || true)"
if [ "$http" = "200" ]; then ok "run_file_allow http=200"; else err "run_file_allow http=$http"; fi

python3 - <<'PY' "$tmp"
import json,sys
fn=sys.argv[1]
s=open(fn,'rb').read()
if not s.strip():
    print("[ERR] empty body")
    sys.exit(3)
try:
    j=json.loads(s.decode('utf-8', errors='replace'))
except Exception as e:
    print("[ERR] JSON parse failed:", e)
    print("first120=", s[:120])
    sys.exit(4)
if "ok" not in j:
    print("[ERR] missing key: ok")
    sys.exit(5)
print("[OK] ok=", j.get("ok"), "keys=", sorted(list(j.keys()))[:14])
PY

ok "run_file_allow JSON parse OK"

echo
echo "== SUMMARY =="
echo "OK=$OK WARN=$WARN ERR=$ERR"
[ "$ERR" -eq 0 ]
