#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TMP_DIR="${TMP_DIR:-/tmp/vsp_p0_selfcheck}"
mkdir -p "$TMP_DIR"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need wc; need date

OK=0; WARN=0; ERR=0
ok(){ echo "[OK] $*"; OK=$((OK+1)); }
warn(){ echo "[WARN] $*"; WARN=$((WARN+1)); }
err(){ echo "[ERR] $*"; ERR=$((ERR+1)); }

http_head(){
  local url="$1" out="$2"
  curl -sS -I "$url" > "$out" || return 1
}
http_get(){
  local url="$1" hdr="$2" body="$3"
  curl -sS -D "$hdr" "$url" -o "$body" || return 1
}

status_from_headers(){
  sed -n '1{s/HTTP\/[^ ]\+ \([0-9]\+\).*/\1/p;q}' "$1"
}

# 1) /
H="$TMP_DIR/root.h"; B="$TMP_DIR/root.html"
if http_get "$BASE/" "$H" "$B"; then
  st="$(status_from_headers "$H")"
  if [[ "$st" =~ ^(200|302)$ ]]; then ok "/ => $st"; else err "/ => $st (expect 200/302)"; fi
else
  err "GET / failed"
fi

# 2) /vsp5
H="$TMP_DIR/vsp5.h"; B="$TMP_DIR/vsp5.html"
if http_get "$BASE/vsp5" "$H" "$B"; then
  st="$(status_from_headers "$H")"
  if [[ "$st" == "200" ]]; then ok "/vsp5 => 200"; else err "/vsp5 => $st (expect 200)"; fi
  bytes="$(wc -c < "$B" | tr -d ' ')"
  if [ "$bytes" -ge 5000 ]; then ok "/vsp5 body size=$bytes"; else warn "/vsp5 body small size=$bytes (check rendering)"; fi
else
  err "GET /vsp5 failed"
fi

# 3) /runs (must be clean: no fill_real markers/script)
H="$TMP_DIR/runs.h"; B="$TMP_DIR/runs.html"
if http_get "$BASE/runs" "$H" "$B"; then
  st="$(status_from_headers "$H")"
  if [[ "$st" == "200" ]]; then ok "/runs => 200"; else err "/runs => $st (expect 200)"; fi

  bytes="$(wc -c < "$B" | tr -d ' ')"
  if [ "$bytes" -ge 1000 ]; then ok "/runs body size=$bytes"; else warn "/runs body small size=$bytes (GET ok but HTML may be empty?)"; fi

  if grep -q "VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY" "$B"; then
    err "/runs still contains fill_real marker"
  else
    ok "/runs no fill_real marker"
  fi

  if grep -q "vsp_fill_real_data_5tabs_p1_v1\.js" "$B"; then
    err "/runs still contains fill_real script"
  else
    ok "/runs no fill_real script"
  fi
else
  err "GET /runs failed"
fi

# 4) /api/vsp/runs?limit=1 (parse JSON to get rid_latest)
H="$TMP_DIR/api_runs.h"; B="$TMP_DIR/api_runs.json"
RID=""
if http_get "$BASE/api/vsp/runs?limit=1" "$H" "$B"; then
  st="$(status_from_headers "$H")"
  if [[ "$st" == "200" ]]; then ok "/api/vsp/runs => 200"; else err "/api/vsp/runs => $st (expect 200)"; fi

  # Optional contract header
  if grep -qi "^X-VSP-RUNS-CONTRACT:" "$H"; then
    ok "X-VSP-RUNS-CONTRACT: $(grep -i '^X-VSP-RUNS-CONTRACT:' "$H" | head -n1 | sed 's/\r$//')"
  else
    warn "missing X-VSP-RUNS-CONTRACT header"
  fi

  RID="$(python3 - <<'PY' "$B"
import json,sys
p=sys.argv[1]
d=json.load(open(p,'r',encoding='utf-8',errors='replace'))
rid = d.get("rid_latest")
if not rid:
    items=d.get("items") or []
    if items and isinstance(items,list):
        rid = items[0].get("run_id")
print(rid or "")
PY
)"
  if [ -n "$RID" ]; then ok "RID latest=$RID"; else err "cannot extract RID from /api/vsp/runs"; fi
else
  err "GET /api/vsp/runs failed"
fi

# 5) Export endpoints (WARN if endpoint missing; ERR if present but broken)
check_endpoint(){
  local name="$1" url="$2" expect="$3"
  local hh="$TMP_DIR/$(echo "$name" | tr ' /' '__').h"
  if http_head "$url" "$hh"; then
    local st
    st="$(status_from_headers "$hh")"
    if [[ "$st" =~ ^(200|302)$ ]]; then
      ok "$name => $st"
      if [ -n "$expect" ] && ! grep -qi "$expect" "$hh"; then
        warn "$name missing header match: $expect"
      fi
    else
      err "$name => $st"
    fi
  else
    warn "$name HEAD failed (endpoint missing?)"
  fi
}

if [ -n "$RID" ]; then
  check_endpoint "export_csv" "$BASE/api/vsp/export_csv?rid=${RID}" "Content-"
  check_endpoint "export_tgz_reports" "$BASE/api/vsp/export_tgz?rid=${RID}&scope=reports" "Content-"
  check_endpoint "sha256_run_gate_summary" "$BASE/api/vsp/sha256?rid=${RID}&name=reports/run_gate_summary.json" "Content-Type: application/json"
fi

echo "== RESULT =="
echo "BASE=$BASE"
echo "OK=$OK WARN=$WARN ERR=$ERR"
echo "TMP_DIR=$TMP_DIR"
[ "$ERR" -eq 0 ] && exit 0 || exit 1
