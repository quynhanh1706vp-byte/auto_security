#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
MODE="${MODE:-import}"           # import|rid
RID="${RID:-}"
TIMEOUT_SEC="${TIMEOUT_SEC:-240}" # poll status max
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

# ---------- [0] base alive ----------
log "== [P550] BASE=$BASE TS=$TS MODE=$MODE =="
if ! curl -fsS --connect-timeout 2 --max-time 5 "$BASE/vsp5" -o "$OUT/vsp5.html"; then
  fail "UI not reachable: $BASE/vsp5"
fi
ok "UI reachable"

# ---------- [1] get RID ----------
if [ "$MODE" = "rid" ]; then
  [ -n "$RID" ] || fail "MODE=rid requires RID=..."
else
  # import RID newest from top_findings_v2 (your “flow chính thống” for ingest)
  if ! fetch_json "$BASE/api/vsp/top_findings_v2?limit=1" "$OUT/top_findings_v2.json"; then
    fail "cannot fetch top_findings_v2"
  fi
  RID="$(python3 - <<'PY' "$OUT/top_findings_v2.json"
import json,sys
j=json.load(open(sys.argv[1],'r',encoding='utf-8',errors='replace'))
print(j.get("rid") or j.get("items",[{}])[0].get("rid") or "")
PY
)"
  [ -n "$RID" ] || fail "cannot derive RID from top_findings_v2"
fi
ok "RID=$RID"
echo "$RID" > "$OUT/RID.txt"

# ---------- [2] poll run_status_v1 ----------
# try both common contracts: /api/vsp/run_status_v1/<rid> and ?rid=<rid>
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
# accept multiple schemas
for k in ("state","status","run_state","phase"):
    if isinstance(j,dict) and j.get(k):
        print(str(j.get(k))); sys.exit(0)
# nested
if isinstance(j,dict):
    rs=j.get("run") or {}
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
      # unknown state: treat as fail (commercial strict)
      fail "unknown run state: $state"
      ;;
  esac
done

if [ "$state" = "DEGRADED" ]; then
  warn "Run is DEGRADED (tool timeout/missing is acceptable but must be visible in UI)"
fi

# ---------- [3] assert 5 UI tabs ----------
log "== [3] assert 5 tabs (200 + non-empty) =="
pages=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${pages[@]}"; do
  f="$OUT/page_$(echo "$p" | tr '/?' '__').html"
  hdr="$OUT/page_$(echo "$p" | tr '/?' '__').hdr"
  code="$(curl -sS -D "$hdr" -o "$f" -w "%{http_code}" --connect-timeout 2 --max-time 10 "$BASE$p" || true)"
  [ "$code" = "200" ] || fail "page $p http=$code"
  sz="$(wc -c <"$f" | awk '{print $1}')"
  [ "$sz" -gt 800 ] || fail "page $p too small ($sz bytes) => likely blank/redirect"
  ok "page $p OK ($sz bytes)"
done

# quick degraded badge expectation on dashboard (non-fatal if UI text differs)
if [ "$state" = "DEGRADED" ]; then
  if grep -qiE "DEGRADED|degraded" "$OUT/page___vsp5.html" "$OUT/page___c__dashboard.html" 2>/dev/null; then
    ok "degraded badge/text seems present"
  else
    warn "degraded state but badge/text not detected by grep (please verify UI renders badge)"
  fi
fi

# ---------- [4] assert ingest artifacts via gateway ----------
log "== [4] ingest sanity: runs_v3 must include RID =="
if fetch_json "$BASE/api/ui/runs_v3?limit=50&include_ci=1" "$OUT/runs_v3.json"; then
  python3 - <<'PY' "$OUT/runs_v3.json" "$RID" || exit 1
import json,sys
j=json.load(open(sys.argv[1],'r',encoding='utf-8',errors='replace'))
rid=sys.argv[2]
items=j.get("items") or j.get("runs") or []
ok=any((it.get("rid")==rid) for it in items if isinstance(it,dict))
print("[OK]" if ok else "[NO]")
sys.exit(0 if ok else 2)
PY
  ok "runs_v3 contains RID"
else
  warn "runs_v3 not available (skip, but should be fixed for commercial Runs & Reports)"
fi

# ---------- [5] export report + support bundle ----------
# We'll probe common endpoints; pass if we successfully download non-empty html+pdf and bundle.
log "== [5] export report + support bundle (RID) =="

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

# candidate endpoints (adjust later as you contractize)
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

if ! download_first_working "HTML" "$html_out" "${html_urls[@]}"; then
  fail "cannot export HTML report (no endpoint worked). see $OUT/tried_HTML.txt"
fi
# basic HTML checks (header + table-ish)
grep -qiE "<html|<head|<body" "$html_out" || fail "HTML report missing basic html tags"
grep -qiE "CRITICAL|HIGH|MEDIUM|LOW|INFO|TRACE" "$html_out" || warn "HTML report: severity words not detected (verify template)"
ok "HTML report sanity OK"

if ! download_first_working "PDF" "$pdf_out" "${pdf_urls[@]}"; then
  fail "cannot export PDF report (no endpoint worked). see $OUT/tried_PDF.txt"
fi
# pdf magic
python3 - <<'PY' "$pdf_out" || exit 1
import sys
p=sys.argv[1]
b=open(p,'rb').read(5)
assert b==b'%PDF-', "not a PDF"
print("[OK] PDF magic")
PY

if ! download_first_working "BUNDLE" "$bundle_out" "${bundle_urls[@]}"; then
  warn "support bundle endpoint not found yet (commercial TODO). see $OUT/tried_BUNDLE.txt"
else
  ok "support bundle downloaded"
fi

# ---------- finish ----------
echo "PASS" > "$OUT/RESULT.txt"
log "== RESULT: PASS (RID=$RID) =="
log "Artifacts: $OUT"
exit 0
