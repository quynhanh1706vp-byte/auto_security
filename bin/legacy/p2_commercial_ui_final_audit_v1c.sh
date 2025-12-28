#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
ERRLOG="${VSP_UI_ERRLOG:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log}"
KEEP_PAYLOADS="${VSP_AUDIT_KEEP_PAYLOADS:-1}"

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

tmp="$(mktemp -d /tmp/vsp_final_audit_v1c_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

{
echo "== VSP Commercial Final Audit (v1c) =="
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

  # dashboard marker
  if [ "$P" = "/vsp5" ]; then
    if grep -q 'id="vsp-dashboard-main"' "$H"; then ok "Dashboard root marker present (id=vsp-dashboard-main)" | tee -a "$REPORT_TXT"; else warn "Dashboard root marker missing" | tee -a "$REPORT_TXT"; fi
  fi

  # extract assets
  # NOTE: capture js/css from src/href with /static/..., keep full URL path+query
  grep -oE '(/static/[^"'"'"' ]+\.(js|css)(\?[^"'"'"' ]*)?)' "$H" \
    | sed 's/&amp;/\&/g' \
    >> "$tmp/assets_all.txt" || true

  js_count="$(grep -oE '(/static/[^"'"'"' ]+\.js(\?[^"'"'"' ]*)?)' "$H" | wc -l | awk '{print $1}')"
  ok "TAB $P js_count=$js_count" | tee -a "$REPORT_TXT"
done

# uniq assets
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
echo "== [C] Duplication check (commercial logic): ignore differences ONLY in query param v ==" | tee -a "$REPORT_TXT"

python3 - "$tmp/assets_uniq.txt" "$PAYLOAD_DIR/dup_report.txt" <<'PY' | tee -a "$REPORT_TXT"
import sys
from urllib.parse import urlparse, parse_qsl, urlencode

assets=[line.strip() for line in open(sys.argv[1], encoding="utf-8", errors="replace") if line.strip()]
dup_report_path=sys.argv[2]

def split_url(u):
    # u is like /static/js/x.js?v=...
    # use urlparse with dummy scheme
    p=urlparse("http://x"+u)
    path=p.path
    qs=parse_qsl(p.query, keep_blank_values=True)
    return path, qs

# group by basename
from collections import defaultdict
by_base=defaultdict(list)
for u in assets:
    path,_=split_url(u)
    base=path.rsplit("/",1)[-1]
    by_base[base].append(u)

suspicious=[]
benign=[]
for base, urls in by_base.items():
    if len(urls) <= 1:
        continue

    # Normalize: remove ONLY 'v' from query; compare the remainder + path
    norm=set()
    raw=set(urls)
    for u in urls:
        path, qs = split_url(u)
        qs2=[(k,v) for (k,v) in qs if k.lower()!="v"]
        norm.add((path, tuple(qs2)))

    if len(norm) == 1:
        benign.append((base, sorted(raw)))
    else:
        suspicious.append((base, sorted(raw), sorted(norm)))

print(f"total_assets={len(assets)}; basenames_with_multi_urls={sum(1 for b in by_base.values() if len(b)>1)}")
print(f"benign_multi_v_only={len(benign)}")
print(f"suspicious_multi_url={len(suspicious)}")

with open(dup_report_path, "w", encoding="utf-8") as f:
    for base, urls in benign:
        f.write(f"[BENIGN] {base} => {len(urls)} urls (differs only by v=)\n")
        for u in urls:
            f.write(f"  - {u}\n")
    for base, urls, norm in suspicious:
        f.write(f"[SUSP] {base} => {len(urls)} urls (differs beyond v=)\n")
        for u in urls:
            f.write(f"  - {u}\n")
        f.write(f"  norm_keys={norm}\n")
PY

if grep -q 'suspicious_multi_url=0' "$REPORT_TXT"; then
  ok "No suspicious duplication beyond v= (benign v-only is acceptable)" | tee -a "$REPORT_TXT"
else
  warn "Suspicious duplication beyond v= detected (see $PAYLOAD_DIR/dup_report.txt)" | tee -a "$REPORT_TXT"
fi
ok "Saved dup report: $PAYLOAD_DIR/dup_report.txt" | tee -a "$REPORT_TXT"

echo | tee -a "$REPORT_TXT"
echo "== [D] API contract ==" | tee -a "$REPORT_TXT"

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print(j.get("rid",""))
PY
)"
echo "rid= $RID" | tee -a "$REPORT_TXT"
if [ -n "$RID" ]; then ok "API rid_latest contract OK" | tee -a "$REPORT_TXT"; else err "API rid_latest empty" | tee -a "$REPORT_TXT"; fi

curl -fsS "$BASE/api/vsp/ui_health_v2" >"$tmp/ui_health.json" || true
python3 - "$tmp/ui_health.json" <<'PY' | tee -a "$REPORT_TXT" || true
import json,sys
try:
  j=json.load(open(sys.argv[1],"r",encoding="utf-8"))
  print("marker=", j.get("marker"))
  ok=j.get("ok") is True and j.get("ready") is True
  print("[PY_OK]" if ok else "[PY_ERR]", "ok=", j.get("ok"), "ready=", j.get("ready"))
except Exception as e:
  print("[PY_ERR] parse failed:", e)
PY

if grep -q '\[PY_OK\]' "$REPORT_TXT"; then ok "API ui_health_v2 contract OK" | tee -a "$REPORT_TXT"; else err "API ui_health_v2 contract FAIL" | tee -a "$REPORT_TXT"; fi

# optional: top_findings + trend (don’t fail hard if endpoints exist but return empty)
curl -fsS "$BASE/api/vsp/top_findings_v1?limit=1" >"$tmp/top1.json" || true
python3 - "$tmp/top1.json" <<'PY' | tee -a "$REPORT_TXT" || true
import json,sys
try:
  j=json.load(open(sys.argv[1],"r",encoding="utf-8"))
  ok=j.get("ok") is True
  print("[PY_OK]" if ok else "[PY_ERR]", "top_findings ok=", j.get("ok"), "run_id=", j.get("run_id"))
except Exception as e:
  print("[PY_ERR] top_findings parse failed:", e)
PY

curl -fsS "$BASE/api/vsp/trend_v1" >"$tmp/trend.json" || true
python3 - "$tmp/trend.json" <<'PY' | tee -a "$REPORT_TXT" || true
import json,sys
try:
  j=json.load(open(sys.argv[1],"r",encoding="utf-8"))
  ok=j.get("ok") is True and (j.get("marker") is not None)
  pts=j.get("points") or []
  print("[PY_OK]" if ok else "[PY_ERR]", "trend ok=", j.get("ok"), "marker=", j.get("marker"), "points=", len(pts))
except Exception as e:
  print("[PY_ERR] trend parse failed:", e)
PY

echo | tee -a "$REPORT_TXT"
echo "== [E] Log hygiene ==" | tee -a "$REPORT_TXT"

if [ -f "$ERRLOG" ]; then
  errlog_size_after="$(stat -c%s "$ERRLOG" 2>/dev/null || wc -c <"$ERRLOG" 2>/dev/null || echo 0)"
  errlog_lines_after="$(wc -l <"$ERRLOG" 2>/dev/null || echo 0)"
  delta=$((errlog_lines_after - errlog_lines_before))
  echo "errlog_lines_after=$errlog_lines_after delta_lines=$delta" | tee -a "$REPORT_TXT"
  if [ "$delta" -gt 50 ]; then
    warn "Error log grew by $delta lines during audit (consider rotate/silence)" | tee -a "$REPORT_TXT"
  else
    ok "Error log growth within threshold" | tee -a "$REPORT_TXT"
  fi
fi

# JSON summary
python3 - <<PY >"$REPORT_JSON"
import json
print(json.dumps({
  "ts":"$TS",
  "base":"$BASE",
  "svc":"$SVC",
  "errlog":"$ERRLOG",
  "ok":$OK,
  "warn":$WARN,
  "err":$ERR
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

# treat WARN as non-fatal for commercial if it’s only benign v-only duplicates
# (the dup logic already only warns for suspicious beyond v=)
if [ "$WARN" -gt 0 ]; then
  echo "[PASS+WARN] commercial audit passed with warnings" | tee -a "$REPORT_TXT"
  exit 0
fi

echo "[PASS] commercial final audit clean" | tee -a "$REPORT_TXT"
