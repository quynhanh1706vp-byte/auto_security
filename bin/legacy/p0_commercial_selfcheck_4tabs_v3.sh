#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TMP="${TMP_DIR:-/tmp/vsp_selfcheck_4tabs}"
mkdir -p "$TMP"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need sed; need awk; need grep; need wc; need date

OK=0; WARN=0; ERR=0
ok(){ echo "[OK] $*"; OK=$((OK+1)); }
warn(){ echo "[WARN] $*"; WARN=$((WARN+1)); }
err(){ echo "[ERR] $*"; ERR=$((ERR+1)); }

code_of(){ curl -sS -o /dev/null -w "%{http_code}" "$1" || echo 000; }
len_of(){ curl -sS "$1" | wc -c | tr -d ' '; }

echo "== VSP commercial selfcheck 4 tabs (v3) =="
echo "[INFO] BASE=$BASE"
echo "[INFO] TS=$(date -Is)"

# 0) Service basic
c="$(code_of "$BASE/vsp5")"
if [ "$c" = "200" ]; then ok "GET /vsp5 => 200"; else err "GET /vsp5 => $c"; fi

# 1) 5 pages (Dashboard + 4 tabs)
tabs=( "vsp5" "runs_reports" "data_source" "settings" "rule_overrides" )
for t in "${tabs[@]}"; do
  url="$BASE/$t"
  c="$(code_of "$url")"
  if [ "$c" != "200" ]; then err "GET /$t => $c"; continue; fi
  l="$(len_of "$url")"
  if [ "${l:-0}" -lt 200 ]; then warn "GET /$t => 200 but small body len=$l"; else ok "GET /$t => 200 len=$l"; fi
done

# 2) Runs API (robust)
HDR="$TMP/runs_headers.txt"
BODY="$TMP/runs_body.txt"
URL="$BASE/api/vsp/runs?limit=1"

http_code="$(curl -sS -D "$HDR" -o "$BODY" -w "%{http_code}" "$URL" || echo 000)"
ct="$(grep -i '^content-type:' "$HDR" | head -n1 | sed 's/^[Cc]ontent-[Tt]ype:[[:space:]]*//')"
blen="$(wc -c < "$BODY" | tr -d ' ')"

if [ "$http_code" != "200" ]; then
  err "GET /api/vsp/runs?limit=1 => $http_code"
else
  ok "GET /api/vsp/runs?limit=1 => 200 (ct='${ct:-?}', len=$blen)"
fi

RID="$(python3 - <<'PY'
import json, sys, pathlib
body = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
body_stripped = body.strip()
if not body_stripped:
    print("")
    raise SystemExit(0)
try:
    j = json.loads(body_stripped)
    it = (j.get("items") or [None])[0] or {}
    print(it.get("run_id") or it.get("rid") or j.get("rid_latest") or "")
except Exception:
    print("")
PY
"$BODY")"

if [ -n "${RID:-}" ]; then
  ok "latest RID => $RID"
else
  err "cannot parse RID from /api/vsp/runs (ct='${ct:-?}', len=$blen)"
  echo "[DBG] runs headers (first 12 lines):"
  sed -n '1,12p' "$HDR" || true
  echo "[DBG] runs body (first 200 chars):"
  head -c 200 "$BODY" || true
  echo
fi

# 3) run_file_allow contract (core artifacts)
if [ -n "${RID:-}" ]; then
  paths=( \
    "reports/run_gate_summary.json" \
    "run_gate_summary.json" \
    "reports/run_gate.json" \
    "run_gate.json" \
    "reports/findings_unified.csv" \
    "findings_unified.json" \
  )
  for p in "${paths[@]}"; do
    url="$BASE/api/vsp/run_file_allow?rid=$RID&path=$p"
    c="$(code_of "$url")"
    if [ "$c" = "200" ]; then ok "run_file_allow 200 $p"; else err "run_file_allow $c $p"; fi
  done
fi

echo "== SUMMARY =="
echo "OK=$OK WARN=$WARN ERR=$ERR"
if [ "$ERR" -gt 0 ]; then exit 2; fi
if [ "$WARN" -gt 0 ]; then exit 1; fi
exit 0
