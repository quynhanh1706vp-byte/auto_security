#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
RELROOT="out_ci/releases"

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p950_lock_${TS}"
mkdir -p "$OUT"
log(){ echo "$*" | tee -a "$OUT/run.log"; }

need(){ command -v "$1" >/dev/null 2>&1 || { log "[FAIL] missing tool: $1"; exit 2; }; }
need curl; need python3; need sha256sum; need awk; need sed; need grep; need date; need head

latest_dir="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n1 || true)"
[ -n "$latest_dir" ] || { log "[FAIL] no RELEASE_UI_* under $RELROOT"; exit 2; }

tgz="$(ls -1 "$latest_dir"/*.tgz 2>/dev/null | head -n1 || true)"
sha="$(ls -1 "$latest_dir"/*.sha256 2>/dev/null | head -n1 || true)"
[ -n "$tgz" ] || { log "[FAIL] no .tgz in $latest_dir"; exit 2; }
[ -n "$sha" ] || { log "[FAIL] no .sha256 in $latest_dir"; exit 2; }

rel_name="$(basename "$latest_dir")"
log "== [P950] COMMERCIAL LOCK =="
log "BASE=$BASE"
log "RELEASE_DIR=$latest_dir"
log "TGZ=$(basename "$tgz")"
log "SHA=$(basename "$sha")"

log "== [1] verify sha256 =="
( cd "$latest_dir" && sha256sum -c "$(basename "$sha")" ) | tee -a "$OUT/sha_verify.txt"

log "== [2] verify GOLDEN marker present (optional but recommended) =="
gold="out_ci/releases/LATEST_GOLDEN.txt"
if [ -f "$gold" ]; then
  cp -f "$gold" "$OUT/LATEST_GOLDEN.txt"
  log "[OK] found $gold"
else
  log "[WARN] missing $gold (you can still ship, but risk of team confusion)"
fi

hit200(){
  local path="$1"
  local url="${BASE}${path}"
  local hdr="$OUT/$(echo "$path" | sed 's#[/ ]#_#g').hdr"
  local code
  code="$(curl -sS -D "$hdr" -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 6 "$url" || true)"
  if [ "$code" != "200" ]; then
    log "[FAIL] $path => HTTP $code"
    return 1
  fi
  echo "$path $code" >> "$OUT/http_200_list.txt"
  return 0
}

log "== [3] tabs 200 OK =="
fail=0
for p in /vsp5 /runs /data_source /c/settings /c/rule_overrides; do
  hit200 "$p" || fail=1
done
[ "$fail" -eq 0 ] || { log "[FAIL] some tabs not 200"; exit 3; }
log "[OK] 5 tabs all 200"

json200(){
  local path="$1"
  local url="${BASE}${path}"
  local body="$OUT/$(echo "$path" | sed 's#[/?&=]#_#g').json"
  local code
  code="$(curl -sS -o "$body" -w "%{http_code}" --connect-timeout 2 --max-time 8 "$url" || true)"
  if [ "$code" != "200" ]; then
    log "[FAIL] API $path => HTTP $code"
    return 1
  fi
  python3 - <<PY 2>/dev/null || { log "[FAIL] API $path not valid JSON"; return 1; }
import json,sys
json.load(open("$body","r",encoding="utf-8"))
print("OK")
PY
  echo "$path $code" >> "$OUT/api_200_list.txt"
  return 0
}

log "== [4] core APIs 200 + JSON =="
fail=0
for p in \
  "/api/vsp/healthz" \
  "/api/vsp/top_findings_v2?limit=1" \
  "/api/ui/runs_v3?limit=1&include_ci=1" \
; do
  json200 "$p" || fail=1
done
[ "$fail" -eq 0 ] || { log "[FAIL] some core APIs failed"; exit 4; }
log "[OK] core APIs OK"

log "== [5] optional: restart service then healthz =="
if command -v systemctl >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1; then
    if sudo -n true >/dev/null 2>&1; then
      log "[OPS] sudo systemctl restart $SVC"
      sudo systemctl restart "$SVC" || { log "[FAIL] restart failed"; exit 5; }
      # wait up to 25s
      ok=0
      for i in $(seq 1 25); do
        code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 4 "$BASE/api/vsp/healthz" || true)"
        log "try#$i healthz=$code"
        if [ "$code" = "200" ]; then ok=1; break; fi
        sleep 1
      done
      [ "$ok" = "1" ] || { log "[FAIL] healthz not 200 after restart"; exit 6; }
      log "[OK] restart + healthz OK"
      sudo journalctl -u "$SVC" --since "5 minutes ago" --no-pager > "$OUT/journal_last5m.txt" || true
    else
      log "[WARN] sudo -n not available; skip restart test"
    fi
  else
    log "[WARN] no sudo; skip restart test"
  fi
else
  log "[WARN] no systemctl; skip restart test"
fi

log "== [6] write COMMERCIAL_LOCK proof =="
cat > "$OUT/COMMERCIAL_LOCK.txt" <<EOF
COMMERCIAL_LOCK=PASS
RELEASE=$rel_name
BASE=$BASE
TGZ=$(basename "$tgz")
SHA256_VERIFY=OK
TABS_200=OK
CORE_APIS_JSON=OK
EVIDENCE_DIR=$OUT
TIME=$TS
EOF

python3 - <<PY
import json, time
o={
  "commercial_lock":"PASS",
  "release":"$rel_name",
  "base":"$BASE",
  "tgz":"$(basename "$tgz")",
  "sha256_verify":"OK",
  "tabs_200":"OK",
  "core_apis_json":"OK",
  "evidence_dir":"$OUT",
  "time":"$TS",
  "epoch":int(time.time()),
}
print(json.dumps(o, indent=2))
open("$OUT/COMMERCIAL_LOCK.json","w",encoding="utf-8").write(json.dumps(o, indent=2))
PY

log "[PASS] COMMERCIAL LOCK complete => $OUT"
