#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
MODE="${MODE:-import}"            # import|rid
RID="${RID:-}"
TIMEOUT_SEC="${TIMEOUT_SEC:-240}"
POLL_SEC="${POLL_SEC:-2}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p550_${TS}"
mkdir -p "$OUT"

log(){ echo "$*" | tee -a "$OUT/gate.log"; }
fail(){ log "[FAIL] $*"; echo "FAIL" > "$OUT/RESULT.txt"; exit 10; }
warn(){ log "[WARN] $*"; echo "DEGRADED" > "$OUT/RESULT.txt"; }
ok(){ log "[OK] $*"; }

need(){ command -v "$1" >/dev/null 2>&1 || fail "missing: $1"; }
need curl; need python3; need awk; need sed; need grep; need wc

fetch_json(){
  local url="$1" out="$2"
  curl -fsS --connect-timeout 2 --max-time 10 "$url" -o "$out" || return 1
  python3 -m json.tool "$out" >/dev/null 2>&1 || return 2
  return 0
}

extract_rid_any(){
  local jf="$1"
  [ -f "$jf" ] || { echo ""; return 0; }
  python3 - "$jf" <<'PY'
import json,sys,re
p=sys.argv[1]
j=json.load(open(p,'r',encoding='utf-8',errors='replace'))

RID_RE=re.compile(r'^(VSP_[A-Z0-9_]+|RUN_[0-9]{8}_[0-9]{6}|VSP_CI_[0-9]{8}_[0-9]{6})$')
PREF_KEYS=set(["rid","RID","run_id","runId","id","runid","rid_latest","latest_rid"])

found=[]
def walk(x):
    if isinstance(x, dict):
        for k in list(x.keys()):
            if k in PREF_KEYS and isinstance(x.get(k), str) and x[k].strip():
                v=x[k].strip()
                if RID_RE.match(v): found.append(v)
        for v in x.values():
            walk(v)
    elif isinstance(x, list):
        for it in x:
            walk(it)
    elif isinstance(x, str):
        s=x.strip()
        if RID_RE.match(s): found.append(s)

walk(j)

seen=set(); out=[]
for v in found:
    if v not in seen:
        out.append(v); seen.add(v)

print(out[0] if out else "")
PY
}

log "== [P550] BASE=$BASE TS=$TS MODE=$MODE =="

# [0] base alive
if ! curl -fsS --connect-timeout 2 --max-time 5 "$BASE/vsp5" -o "$OUT/vsp5.html"; then
  fail "UI not reachable: $BASE/vsp5"
fi
ok "UI reachable"

# [1] RID
if [ "$MODE" = "rid" ]; then
  [ -n "$RID" ] || fail "MODE=rid requires RID=..."
else
  if fetch_json "$BASE/api/ui/runs_v3?limit=5&include_ci=1" "$OUT/runs_v3.json"; then
    RID="$(extract_rid_any "$OUT/runs_v3.json")"
  fi

  if [ -z "${RID:-}" ]; then
    if fetch_json "$BASE/api/vsp/top_findings_v2?limit=1" "$OUT/top_findings_v2.json"; then
      RID="$(extract_rid_any "$OUT/top_findings_v2.json")"
    fi
  fi

  if [ -z "${RID:-}" ]; then
    if fetch_json "$BASE/api/vsp/runs_v3?limit=5" "$OUT/vsp_runs_v3.json"; then
      RID="$(extract_rid_any "$OUT/vsp_runs_v3.json")"
    fi
  fi

  if [ -z "${RID:-}" ]; then
    log "[DIAG] cannot find RID. dumping keys snapshot:"
    for f in "$OUT"/runs_v3.json "$OUT"/top_findings_v2.json "$OUT"/vsp_runs_v3.json; do
      [ -f "$f" ] || continue
      log "---- $f (first 80 lines) ----"
      sed -n '1,80p' "$f" | tee -a "$OUT/gate.log" >/dev/null || true
    done
    fail "cannot derive RID (see $OUT/*.json)"
  fi
fi

ok "RID=$RID"
echo "$RID" > "$OUT/RID.txt"

# [2] poll run_status_v1
status_url_1="$BASE/api/vsp/run_status_v1/$RID"
status_url_2="$BASE/api/vsp/run_status_v1?rid=$RID"

state=""
deadline=$(( $(date +%s) + TIMEOUT_SEC ))
log "== [2] poll run_status_v1 (timeout ${TIMEOUT_SEC}s) =="

while :; do
  now=$(date +%s)
  [ "$now" -le "$deadline" ] || fail "run_status_v1 timeout after ${TIMEOUT_SEC}s (RID=$RID)"

  if fetch_json "$status_url_1" "$OUT/run_status.json"; then
    :
  elif fetch_json "$status_url_2" "$OUT/run_status.json"; then
    :
  else
    log "[poll] run_status_v1 not available yet..."
    sleep "$POLL_SEC"
    continue
  fi

  state="$(python3 - <<'PY' "$OUT/run_status.json"
import json,sys
j=json.load(open(sys.argv[1],'r',encoding='utf-8',errors='replace'))
for k in ("state","status","run_state","phase"):
    if isinstance(j,dict) and j.get(k):
        print(str(j.get(k))); sys.exit(0)
rs=(j.get("run") if isinstance(j,dict) else None) or {}
for k in ("state","status","run_state","phase"):
    if isinstance(rs,dict) and rs.get(k):
        print(str(rs.get(k))); sys.exit(0)
print("")
PY
)"
  log "[poll] state=${state:-<empty>}"
  echo "$state" > "$OUT/run_state_last.txt"

  case "$state" in
    RUNNING|STARTING|QUEUED|"")
      sleep "$POLL_SEC"
      ;;
    FINISHED|DEGRADED)
      ok "run_status_v1 done: $state"
      echo "$state" > "$OUT/run_state_final.txt"
      break
      ;;
    FAILED|ERROR)
      fail "run_status_v1 failed: $state"
      ;;
    *)
      fail "unknown run state: $state"
      ;;
  esac
done

if [ "$state" = "DEGRADED" ]; then
  warn "Run is DEGRADED (tool timeout/missing acceptable but must be visible)"
fi

# [3] assert 5 tabs
log "== [3] assert 5 tabs =="
pages=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${pages[@]}"; do
  f="$OUT/page_$(echo "$p" | tr '/?' '__').html"
  hdr="$OUT/page_$(echo "$p" | tr '/?' '__').hdr"
  code="$(curl -sS -D "$hdr" -o "$f" -w "%{http_code}" --connect-timeout 2 --max-time 10 "$BASE$p" || true)"
  [ "$code" = "200" ] || fail "page $p http=$code"
  sz="$(wc -c <"$f" | awk '{print $1}')"
  [ "$sz" -gt 800 ] || fail "page $p too small ($sz bytes) => likely blank"
  ok "page $p OK ($sz bytes)"
done

# [4] ingest sanity
log "== [4] ingest sanity: runs_v3 contains RID =="
if fetch_json "$BASE/api/ui/runs_v3?limit=50&include_ci=1" "$OUT/runs_v3_check.json"; then
  python3 - <<'PY' "$OUT/runs_v3_check.json" "$RID"
import json,sys
j=json.load(open(sys.argv[1],'r',encoding='utf-8',errors='replace'))
rid=sys.argv[2]
items=j.get("items") or j.get("runs") or []
ok=any((isinstance(it,dict) and it.get("rid")==rid) for it in items)
print("[OK]" if ok else "[NO]")
sys.exit(0 if ok else 2)
PY
  ok "runs_v3 contains RID"
else
  warn "runs_v3 not available"
fi

# [5] export report
log "== [5] export report =="

download_first_working(){
  local kind="$1" outfile="$2"; shift 2
  local tried="$OUT/tried_${kind}.txt"; : >"$tried"
  for url in "$@"; do
    echo "$url" >> "$tried"
    hdr="${outfile}.hdr"
    if curl -fsS -D "$hdr" --connect-timeout 2 --max-time 30 "$url" -o "$outfile"; then
      sz="$(wc -c <"$outfile" | awk '{print $1}')"
      if [ "$sz" -gt 0 ]; then
        ok "$kind downloaded: $(basename "$outfile") ($sz bytes)"
        echo "$url" > "${outfile}.url"
        return 0
      fi
    fi
  done
  return 1
}

html_out="$OUT/report_${RID}.html"
pdf_out="$OUT/report_${RID}.pdf"
bundle_out="$OUT/support_bundle_${RID}.tgz"

html_urls=(
  "$BASE/api/vsp/export_html_v1?rid=$RID"
  "$BASE/api/vsp/report_html_v1?rid=$RID"
  "$BASE/api/vsp/export_report_v1?rid=$RID&fmt=html"
  "$BASE/api/vsp/report_export_v1?rid=$RID&fmt=html"
)
pdf_urls=(
  "$BASE/api/vsp/export_pdf_v1?rid=$RID"
  "$BASE/api/vsp/report_pdf_v1?rid=$RID"
  "$BASE/api/vsp/export_report_v1?rid=$RID&fmt=pdf"
  "$BASE/api/vsp/report_export_v1?rid=$RID&fmt=pdf"
)
bundle_urls=(
  "$BASE/api/vsp/support_bundle_v1?rid=$RID"
  "$BASE/api/vsp/bundle_support_v1?rid=$RID"
  "$BASE/api/vsp/export_support_bundle_v1?rid=$RID"
)

download_first_working "HTML" "$html_out" "${html_urls[@]}" \
  || fail "cannot export HTML (see $OUT/tried_HTML.txt)"
grep -qiE "<html|<head|<body" "$html_out" || fail "HTML missing basic tags"

download_first_working "PDF" "$pdf_out" "${pdf_urls[@]}" \
  || fail "cannot export PDF (see $OUT/tried_PDF.txt)"
python3 - <<'PY' "$pdf_out"
import sys
b=open(sys.argv[1],'rb').read(5)
assert b==b'%PDF-', "not a PDF"
print("[OK] PDF magic")
PY

if ! download_first_working "BUNDLE" "$bundle_out" "${bundle_urls[@]}"; then
  warn "support bundle endpoint not found yet (TODO). see $OUT/tried_BUNDLE.txt"
else
  ok "support bundle downloaded"
fi

echo "PASS" > "$OUT/RESULT.txt"
log "== RESULT: PASS (RID=$RID) =="
log "Artifacts: $OUT"
exit 0
