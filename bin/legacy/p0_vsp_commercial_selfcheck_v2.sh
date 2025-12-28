#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TMP="${TMP_DIR:-/tmp/vsp_commercial_selfcheck}"
mkdir -p "$TMP"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need wc

OK=0; WARN=0; ERR=0
ok(){ echo "[OK] $*"; OK=$((OK+1)); }
warn(){ echo "[WARN] $*"; WARN=$((WARN+1)); }
err(){ echo "[ERR] $*"; ERR=$((ERR+1)); }

head_ok(){
  local url="$1"
  local out="$TMP/head.$(echo "$url" | tr '/:?&=' '____').txt"
  if curl -sS -I "$url" > "$out"; then
    local code; code="$(awk 'NR==1{print $2}' "$out")"
    if [ "$code" = "200" ]; then ok "HEAD 200 $url"; return 0; fi
    warn "HEAD $code $url"; return 0
  else
    err "HEAD failed $url"; return 1
  fi
}

get_size(){
  local url="$1"
  local out="$TMP/body.$(echo "$url" | tr '/:?&=' '____').bin"
  if curl -sS "$url" > "$out"; then
    local n; n="$(wc -c < "$out" | tr -d ' ')"
    echo "$n"
    return 0
  else
    echo "0"
    return 1
  fi
}

json_get(){
  local url="$1"
  local out="$TMP/json.$(echo "$url" | tr '/:?&=' '____').json"
  if curl -sS "$url" > "$out"; then
    echo "$out"
    return 0
  else
    return 1
  fi
}

echo "== VSP Commercial Selfcheck v2 =="
echo "[BASE] $BASE"
echo

# 1) 5 tabs
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  head_ok "$BASE$p" || true
  sz="$(get_size "$BASE$p" || true)"
  if [ "${sz:-0}" -gt 200 ]; then ok "BODY non-trivial ${p} size=$sz"; else warn "BODY small ${p} size=$sz"; fi
done

echo
# 2) runs meta + pick gate_root
META_FILE="$(json_get "$BASE/api/vsp/runs?_ts=$(date +%s)" || true)"
if [ -n "${META_FILE:-}" ] && [ -s "$META_FILE" ]; then
  ok "/api/vsp/runs ok"
else
  err "/api/vsp/runs failed"
  META_FILE=""
fi

RID=""
if [ -n "$META_FILE" ]; then
  RID="$(python3 - <<PY
import json
p=r"$META_FILE"
j=json.load(open(p,"r",encoding="utf-8",errors="replace"))
rid=j.get("rid_latest_gate_root") or j.get("rid_latest") or j.get("rid_last_good") or j.get("rid_latest_findings") or ""
print(rid)
PY
)"
fi

if [ -n "$RID" ]; then
  ok "gate_root RID=$RID"
else
  err "cannot pick gate_root RID from /api/vsp/runs"
fi

echo
# 3) evidence probes via run_file_allow
probe(){
  local path="$1"
  local url="$BASE/api/vsp/run_file_allow?rid=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$RID")&path=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$path")&_ts=$(date +%s)"
  local n; n="$(get_size "$url" || true)"
  if [ "${n:-0}" -gt 2 ]; then ok "evidence OK $path ($n bytes)"; else warn "evidence missing/empty $path ($n bytes)"; fi
}

if [ -n "$RID" ]; then
  probe "run_manifest.json"
  probe "run_evidence_index.json"
  probe "run_gate.json"
  probe "run_gate_summary.json"
  probe "findings_unified.json"
  probe "reports/findings_unified.csv"
  probe "reports/findings_unified.sarif"
fi

echo
# 4) export endpoints existence (P0 demo)
for ep in "/api/vsp/run_export_zip?rid=$RID" "/api/vsp/run_export_pdf?rid=$RID"; do
  if curl -sS -I "$BASE$ep" >/dev/null 2>&1; then
    code="$(curl -sS -I "$BASE$ep" | awk 'NR==1{print $2}')"
    if [ "$code" = "200" ]; then ok "export 200 $ep"; else warn "export $code $ep"; fi
  else
    warn "export HEAD failed $ep"
  fi
done

echo
echo "== SUMMARY =="
echo "OK=$OK WARN=$WARN ERR=$ERR"
if [ "$ERR" -gt 0 ]; then
  echo "[VERDICT] RED (must fix ERR first)"
elif [ "$WARN" -gt 0 ]; then
  echo "[VERDICT] AMBER (acceptable for dev/demo; fix before commercial)"
else
  echo "[VERDICT] GREEN (commercial-ready snapshot)"
fi
