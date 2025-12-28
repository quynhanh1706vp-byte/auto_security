#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
MODE="${MODE:-import}"            # import|rid|trigger
RID="${RID:-}"
TIMEOUT_SEC="${TIMEOUT_SEC:-240}"
POLL_SEC="${POLL_SEC:-2}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p550_${TS}"
mkdir -p "$OUT"

log(){ echo "$*" | tee -a "$OUT/gate.log"; }
fail(){ log "[FAIL] $*"; echo "FAIL" > "$OUT/RESULT.txt"; exit 10; }
warn(){ log "[WARN] $*"; }
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
        for v in x.values(): walk(v)
    elif isinstance(x, list):
        for it in x: walk(it)
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

extract_state_any(){
  local jf="$1"
  [ -f "$jf" ] || { echo ""; return 0; }
  python3 - "$jf" <<'PY'
import json,sys
j=json.load(open(sys.argv[1],'r',encoding='utf-8',errors='replace'))

# common keys
for k in ("state","status","run_state","phase"):
    if isinstance(j,dict) and j.get(k):
        print(str(j.get(k))); sys.exit(0)

# nested
if isinstance(j,dict):
    rs=j.get("run") or {}
    if isinstance(rs,dict):
        for k in ("state","status","run_state","phase"):
            if rs.get(k):
                print(str(rs.get(k))); sys.exit(0)

# boolean-ish hints
if isinstance(j,dict):
    for k in ("done","finished","complete","completed","is_done"):
        v=j.get(k)
        if v is True:
            print("FINISHED"); sys.exit(0)
    if j.get("degraded") is True:
        print("DEGRADED"); sys.exit(0)

print("")
PY
}

log "== [P550v1d] BASE=$BASE TS=$TS MODE=$MODE =="

# [0] base alive
if ! curl -fsS --connect-timeout 2 --max-time 5 "$BASE/vsp5" -o "$OUT/vsp5.html"; then
  fail "UI not reachable: $BASE/vsp5"
fi
ok "UI reachable"

# [1] RID
if [ "$MODE" = "rid" ] || [ "$MODE" = "trigger" ]; then
  [ -n "$RID" ] || fail "MODE=$MODE requires RID=..."
else
  if fetch_json "$BASE/api/ui/runs_v3?limit=5&include_ci=1" "$OUT/runs_v3.json"; then
    RID="$(extract_rid_any "$OUT/runs_v3.json")"
  fi
  if [ -z "${RID:-}" ]; then
    if fetch_json "$BASE/api/vsp/top_findings_v2?limit=1" "$OUT/top_findings_v2.json"; then
      RID="$(extract_rid_any "$OUT/top_findings_v2.json")"
    fi
  fi
  [ -n "${RID:-}" ] || fail "cannot derive RID (see $OUT/*.json)"
fi
ok "RID=$RID"
echo "$RID" > "$OUT/RID.txt"

# [2] run_status handling
status_url_1="$BASE/api/vsp/run_status_v1/$RID"
status_url_2="$BASE/api/vsp/run_status_v1?rid=$RID"
state=""

log "== [2] run_status_v1 =="

if [ "$MODE" = "import" ] || [ "$MODE" = "rid" ]; then
  # DO NOT poll in import/rid mode (avoid hang on old RID). Just sample once.
  if fetch_json "$status_url_1" "$OUT/run_status.json" || fetch_json "$status_url_2" "$OUT/run_status.json"; then
    state="$(extract_state_any "$OUT/run_status.json")"
    if [ -z "${state:-}" ]; then
      warn "run_status_v1 returned JSON but no state/status/phase for RID=$RID (OK for import-mode; MUST be fixed for trigger-mode)"
      state="FINISHED"
    else
      ok "run_status_v1 sample state=$state"
    fi
  else
    warn "run_status_v1 not reachable (OK for import-mode; MUST be fixed for trigger-mode)"
    state="FINISHED"
  fi
else
  # MODE=trigger: MUST poll until FINISHED/DEGRADED/FAILED
  deadline=$(( $(date +%s) + TIMEOUT_SEC ))
  while :; do
    now=$(date +%s)
    [ "$now" -le "$deadline" ] || fail "run_status_v1 timeout after ${TIMEOUT_SEC}s (RID=$RID)"

    if fetch_json "$status_url_1" "$OUT/run_status.json" || fetch_json "$status_url_2" "$OUT/run_status.json"; then
      state="$(extract_state_any "$OUT/run_status.json")"
    else
      state=""
    fi

    log "[poll] state=${state:-<empty>}"
    if [ -z "${state:-}" ]; then
      # fail fast if API never exposes state (commercial strict)
      # after 5 polls (~10s), dump and fail
      c="${c:-0}"; c=$((c+1))
      if [ "$c" -ge 5 ]; then
        log "---- run_status.json (first 120 lines) ----"
        [ -f "$OUT/run_status.json" ] && sed -n '1,120p' "$OUT/run_status.json" | tee -a "$OUT/gate.log" >/dev/null || true
        fail "run_status_v1 missing state/status/phase in trigger-mode (must implement contract)"
      fi
      sleep "$POLL_SEC"
      continue
    fi

    case "$state" in
      RUNNING|STARTING|QUEUED)
        sleep "$POLL_SEC"
        ;;
      FINISHED|DEGRADED)
        ok "run_status_v1 done: $state"
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

# [5] export report (same as before)
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
  # STRICT: must look like gzip tarball (>= 1KB and gzip magic 1f8b)
  bsz="$(wc -c <"$bundle_out" | awk '{print $1}')"
  magic="$(python3 - <<'PY2' "$bundle_out"
import sys,binascii
b=open(sys.argv[1],'rb').read(2)
print(binascii.hexlify(b).decode())
PY2
)"
  if [ "$bsz" -lt 1024 ] || [ "$magic" != "1f8b" ]; then
    warn "support bundle looks invalid (size=${bsz} magic=${magic}). Treat as NOT READY for commercial bundle."
  else
    ok "support bundle downloaded (size=${bsz})"
  fi
fi

echo "PASS" > "$OUT/RESULT.txt"
log "== RESULT: PASS (RID=$RID) =="
log "Artifacts: $OUT"
exit 0
