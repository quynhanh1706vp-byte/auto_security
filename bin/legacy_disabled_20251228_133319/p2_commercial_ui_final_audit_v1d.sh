#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
ERRLOG="${VSP_UI_ERRLOG:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need head; need sort; need uniq; need wc; need date; need mktemp

OK=0; WARN=0; ERR=0
ok(){ echo "[OK]   $*"; OK=$((OK+1)); }
warn(){ echo "[WARN] $*"; WARN=$((WARN+1)); }
err(){ echo "[ERR]  $*"; ERR=$((ERR+1)); }

TS="$(date +%Y%m%d_%H%M%S)"
PAYLOAD_DIR="out_ci/final_audit_${TS}_payloads"
mkdir -p "$PAYLOAD_DIR"
REPORT_TXT="out_ci/final_audit_${TS}.txt"
REPORT_JSON="out_ci/final_audit_${TS}.json"

tmp="$(mktemp -d /tmp/vsp_final_audit_v1d_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

api_get_json(){
  # args: URL out_json out_meta
  local url="$1" out_json="$2" out_meta="$3"
  local i=0
  for i in 1 2 3; do
    local hdr="$tmp/hdr_${i}.txt" body="$tmp/body_${i}.bin"
    local http
    http="$(curl -sS -D "$hdr" -o "$body" -w "%{http_code}" "$url" || true)"
    local ctype
    ctype="$(awk -F': ' 'tolower($1)=="content-type"{print $2}' "$hdr" | tr -d '\r' | tail -n 1)"
    printf '{"attempt":%d,"http":"%s","content_type":"%s"}\n' "$i" "$http" "${ctype:-}" >"$out_meta"

    # accept only JSON + 200
    if [ "$http" = "200" ] && echo "${ctype:-}" | grep -qi 'application/json'; then
      cp -f "$body" "$out_json"
      return 0
    fi

    # save evidence for this attempt
    mkdir -p "$PAYLOAD_DIR/api_evidence"
    cp -f "$hdr"  "$PAYLOAD_DIR/api_evidence/$(basename "$out_json").att${i}.headers.txt"
    cp -f "$body" "$PAYLOAD_DIR/api_evidence/$(basename "$out_json").att${i}.body.bin"

    # tiny backoff
    sleep 0.2
  done
  return 1
}

{
echo "== VSP Commercial Final Audit (v1d) =="
echo "ts=$TS"
echo "BASE=$BASE"
echo "SVC=$SVC"
echo "ERRLOG=$ERRLOG"
echo "PAYLOAD_DIR=$PAYLOAD_DIR"
echo
} | tee "$REPORT_TXT"

# systemd + errlog baseline
if command -v systemctl >/dev/null 2>&1; then
  if sudo systemctl is-active --quiet "$SVC"; then ok "systemd $SVC active"; else err "systemd $SVC not active"; fi
else
  warn "systemctl not found; skip service check"
fi

errlog_size_before=0; errlog_lines_before=0
if [ -f "$ERRLOG" ]; then
  errlog_size_before="$(stat -c%s "$ERRLOG" 2>/dev/null || wc -c <"$ERRLOG" 2>/dev/null || echo 0)"
  errlog_lines_before="$(wc -l <"$ERRLOG" 2>/dev/null || echo 0)"
  ok "errlog_size_before=${errlog_size_before} bytes"
  ok "errlog_lines_before=${errlog_lines_before}"
else
  warn "ERRLOG not found: $ERRLOG"
fi

tabs=(/vsp5 /runs /data_source /settings /rule_overrides)

echo | tee -a "$REPORT_TXT"
echo "== [A] UI tabs: HTML 200 + extract assets ==" | tee -a "$REPORT_TXT"

> "$tmp/assets_all.txt"
for P in "${tabs[@]}"; do
  H="$tmp/page_${P//\//_}.html"
  code="$(curl -sS -o "$H" -w "%{http_code}" "$BASE$P" || true)"
  if [ "$code" = "200" ]; then
    ok "TAB $P HTTP=200" | tee -a "$REPORT_TXT"
  else
    err "TAB $P HTTP=$code" | tee -a "$REPORT_TXT"
    continue
  fi

  if [ "$P" = "/vsp5" ]; then
    if grep -q 'id="vsp-dashboard-main"' "$H"; then ok "Dashboard root marker present (id=vsp-dashboard-main)" | tee -a "$REPORT_TXT"; else warn "Dashboard root marker missing" | tee -a "$REPORT_TXT"; fi
  fi

  grep -oE '(/static/[^"'"'"' ]+\.(js|css)(\?[^"'"'"' ]*)?)' "$H" \
    | sed 's/&amp;/\&/g' \
    >> "$tmp/assets_all.txt" || true

  js_count="$(grep -oE '(/static/[^"'"'"' ]+\.js(\?[^"'"'"' ]*)?)' "$H" | wc -l | awk '{print $1}')"
  ok "TAB $P js_count=$js_count" | tee -a "$REPORT_TXT"
done

sort -u "$tmp/assets_all.txt" > "$tmp/assets_uniq.txt"
cp -f "$tmp/assets_uniq.txt" "$PAYLOAD_DIR/assets_uniq.txt"

js_uniq="$(grep -c '\.js' "$tmp/assets_uniq.txt" || true)"
css_uniq="$(grep -c '\.css' "$tmp/assets_uniq.txt" || true)"
total_uniq="$(wc -l <"$tmp/assets_uniq.txt" | awk '{print $1}')"
ok "assets_uniq_total=$((total_uniq)) (js=$js_uniq css=$css_uniq)" | tee -a "$REPORT_TXT"

echo | tee -a "$REPORT_TXT"
echo "== [B] Assets: JS/CSS 200 OK ==" | tee -a "$REPORT_TXT"

bad_assets=0
while IFS= read -r u; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  if [ "$code" != "200" ]; then
    bad_assets=$((bad_assets+1))
    echo "[BAD] $code $u" >> "$PAYLOAD_DIR/assets_bad.txt"
  fi
done < "$tmp/assets_uniq.txt"

if [ "$bad_assets" -eq 0 ]; then
  ok "All referenced assets return 200" | tee -a "$REPORT_TXT"
else
  err "Found $bad_assets assets not 200 (see $PAYLOAD_DIR/assets_bad.txt)" | tee -a "$REPORT_TXT"
fi

echo | tee -a "$REPORT_TXT"
echo "== [C] Duplication check (commercial): ignore v= only ==" | tee -a "$REPORT_TXT"

python3 - "$tmp/assets_uniq.txt" "$PAYLOAD_DIR/dup_report.txt" <<'PY' | tee -a "$REPORT_TXT"
import sys
from urllib.parse import urlparse, parse_qsl
from collections import defaultdict

assets=[line.strip() for line in open(sys.argv[1], encoding="utf-8", errors="replace") if line.strip()]
dup_report_path=sys.argv[2]

def split_url(u):
    p=urlparse("http://x"+u)
    return p.path, parse_qsl(p.query, keep_blank_values=True)

by_base=defaultdict(list)
for u in assets:
    path,_=split_url(u)
    base=path.rsplit("/",1)[-1]
    by_base[base].append(u)

benign=[]
susp=[]
for base, urls in by_base.items():
    if len(urls) <= 1: 
        continue
    norm=set()
    for u in urls:
        path, qs = split_url(u)
        qs2=[(k,v) for (k,v) in qs if k.lower()!="v"]
        norm.add((path, tuple(qs2)))
    if len(norm)==1:
        benign.append((base, sorted(set(urls))))
    else:
        susp.append((base, sorted(set(urls)), sorted(norm)))

print(f"total_assets={len(assets)}; basenames_with_multi_urls={sum(1 for b in by_base.values() if len(b)>1)}")
print(f"benign_multi_v_only={len(benign)}")
print(f"suspicious_multi_url={len(susp)}")

with open(dup_report_path,"w",encoding="utf-8") as f:
    for base, urls in benign:
        f.write(f"[BENIGN] {base} (differs only by v=)\n")
        for u in urls: f.write(f"  - {u}\n")
    for base, urls, norm in susp:
        f.write(f"[SUSP] {base} (differs beyond v=)\n")
        for u in urls: f.write(f"  - {u}\n")
        f.write(f"  norm_keys={norm}\n")
PY

if grep -q 'suspicious_multi_url=0' "$REPORT_TXT"; then
  ok "No suspicious duplication beyond v=" | tee -a "$REPORT_TXT"
else
  warn "Suspicious duplication beyond v= detected (see $PAYLOAD_DIR/dup_report.txt)" | tee -a "$REPORT_TXT"
fi
ok "Saved dup report: $PAYLOAD_DIR/dup_report.txt" | tee -a "$REPORT_TXT"

echo | tee -a "$REPORT_TXT"
echo "== [D] API contract (retry + evidence) ==" | tee -a "$REPORT_TXT"

# rid_latest
rid_json="$tmp/rid_latest.json"
rid_meta="$tmp/rid_latest.meta.jsonl"
if api_get_json "$BASE/api/vsp/rid_latest" "$rid_json" "$rid_meta"; then
  RID="$(python3 - <<PY
import json
j=json.load(open("$rid_json","r",encoding="utf-8"))
print(j.get("rid",""))
PY
)"
  echo "rid= $RID" | tee -a "$REPORT_TXT"
  [ -n "$RID" ] && ok "API rid_latest contract OK" | tee -a "$REPORT_TXT" || err "API rid_latest empty" | tee -a "$REPORT_TXT"
else
  err "API rid_latest not JSON/200 after retries (see $PAYLOAD_DIR/api_evidence)" | tee -a "$REPORT_TXT"
fi

# ui_health_v2
uh_json="$tmp/ui_health.json"
uh_meta="$tmp/ui_health.meta.jsonl"
if api_get_json "$BASE/api/vsp/ui_health_v2" "$uh_json" "$uh_meta"; then
  python3 - <<PY | tee -a "$REPORT_TXT"
import json
j=json.load(open("$uh_json","r",encoding="utf-8"))
print("marker=", j.get("marker"))
print("ok=", j.get("ok"), "ready=", j.get("ready"))
print("meta.asset_v=", (j.get("meta") or {}).get("asset_v"))
PY
  ok "API ui_health_v2 contract OK" | tee -a "$REPORT_TXT"
else
  err "API ui_health_v2 not JSON/200 after retries (see $PAYLOAD_DIR/api_evidence)" | tee -a "$REPORT_TXT"
fi

# top_findings_v1 (soft)
tf_json="$tmp/top_findings.json"
tf_meta="$tmp/top_findings.meta.jsonl"
if api_get_json "$BASE/api/vsp/top_findings_v1?limit=1" "$tf_json" "$tf_meta"; then
  python3 - <<PY | tee -a "$REPORT_TXT"
import json
j=json.load(open("$tf_json","r",encoding="utf-8"))
print("top_findings ok=", j.get("ok"), "run_id=", j.get("run_id"), "total=", j.get("total"))
PY
  ok "API top_findings_v1 OK" | tee -a "$REPORT_TXT"
else
  warn "API top_findings_v1 not JSON/200 (see $PAYLOAD_DIR/api_evidence)" | tee -a "$REPORT_TXT"
fi

# trend_v1 (soft)
tr_json="$tmp/trend.json"
tr_meta="$tmp/trend.meta.jsonl"
if api_get_json "$BASE/api/vsp/trend_v1" "$tr_json" "$tr_meta"; then
  python3 - <<PY | tee -a "$REPORT_TXT"
import json
j=json.load(open("$tr_json","r",encoding="utf-8"))
pts=j.get("points") or []
print("trend ok=", j.get("ok"), "marker=", j.get("marker"), "points=", len(pts))
PY
  ok "API trend_v1 OK" | tee -a "$REPORT_TXT"
else
  warn "API trend_v1 not JSON/200 (see $PAYLOAD_DIR/api_evidence)" | tee -a "$REPORT_TXT"
fi

echo | tee -a "$REPORT_TXT"
echo "== [E] Log hygiene ==" | tee -a "$REPORT_TXT"
if [ -f "$ERRLOG" ]; then
  errlog_lines_after="$(wc -l <"$ERRLOG" 2>/dev/null || echo 0)"
  delta=$((errlog_lines_after - errlog_lines_before))
  echo "errlog_lines_after=$errlog_lines_after delta_lines=$delta" | tee -a "$REPORT_TXT"
  if [ "$delta" -gt 80 ]; then
    warn "Error log grew by $delta lines during audit (consider rotate/silence)" | tee -a "$REPORT_TXT"
  else
    ok "Error log growth within threshold" | tee -a "$REPORT_TXT"
  fi
fi

python3 - <<PY >"$REPORT_JSON"
import json
print(json.dumps({
  "ts":"$TS","base":"$BASE","svc":"$SVC","errlog":"$ERRLOG",
  "ok":$OK,"warn":$WARN,"err":$ERR
}, indent=2))
PY

echo | tee -a "$REPORT_TXT"
echo "== SUMMARY ==" | tee -a "$REPORT_TXT"
echo "OK=$OK WARN=$WARN ERR=$ERR" | tee -a "$REPORT_TXT"
echo "[OK] Saved audit report: $REPORT_TXT" | tee -a "$REPORT_TXT"
echo "[OK] Saved audit json:   $REPORT_JSON" | tee -a "$REPORT_TXT"

if [ "$ERR" -gt 0 ]; then
  echo "[FAIL] commercial final audit has ERR" | tee -a "$REPORT_TXT"
  exit 1
fi
echo "[PASS] commercial final audit (v1d) complete" | tee -a "$REPORT_TXT"
