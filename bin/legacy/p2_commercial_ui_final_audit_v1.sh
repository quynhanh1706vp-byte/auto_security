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

ts="$(date +%Y%m%d_%H%M%S)"
tmp="$(mktemp -d /tmp/vsp_final_audit_${ts}_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

OUTDIR="out_ci"
mkdir -p "$OUTDIR"
REPORT_TXT="${OUTDIR}/final_audit_${ts}.txt"
REPORT_JSON="${OUTDIR}/final_audit_${ts}.json"

# ---------- helpers ----------
http_code(){
  curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 8 "$1" || echo "000"
}

get_file_size(){
  local f="$1"
  if [ -f "$f" ]; then
    stat -c%s "$f" 2>/dev/null || wc -c <"$f" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

json_check(){
  # usage: json_check "<name>" "<url>" "<python_expr_returns_empty_on_ok>"
  local name="$1" url="$2" py="$3"
  local code
  code="$(http_code "$url")"
  if [ "$code" != "200" ]; then
    err "API $name HTTP=$code url=$url"
    return 0
  fi
  # save payload for later debug if needed
  curl -sS "$url" > "$tmp/${name}.json" || true
  python3 - "$tmp/${name}.json" "$name" <<PY
import json,sys
p=sys.argv[1]; name=sys.argv[2]
try:
  j=json.load(open(p,"r",encoding="utf-8"))
except Exception as e:
  print(f"[ERR] API {name} invalid JSON: {e}")
  sys.exit(2)

# minimal baseline: ok=true
if j.get("ok") is not True:
  print(f"[ERR] API {name} ok!=true (ok={j.get('ok')})")
  sys.exit(2)

# custom contract checks (injected by shell via heredoc replacement)
PY
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "API $name contract OK"
  else
    err "API $name contract FAIL (see $tmp/${name}.json)"
  fi
}

# ---------- start ----------
{
echo "== VSP Commercial Final Audit =="
echo "ts=$ts"
echo "BASE=$BASE"
echo "SVC=$SVC"
echo "ERRLOG=$ERRLOG"
echo
} | tee "$REPORT_TXT"

# service status (best effort)
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet "$SVC"; then ok "systemd $SVC active"; else warn "systemd $SVC not active (or not found)"; fi
else
  warn "systemctl not found; skip service check"
fi

# log growth baseline
err_before="$(get_file_size "$ERRLOG")"
ok "errlog_size_before=$err_before bytes"

# ---------- [A] UI 5 tabs ----------
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)

echo | tee -a "$REPORT_TXT"
echo "== [A] UI tabs: HTML 200 + extract assets ==" | tee -a "$REPORT_TXT"

: > "$tmp/all_assets.txt"
: > "$tmp/all_js.txt"
: > "$tmp/all_css.txt"

for p in "${tabs[@]}"; do
  url="${BASE}${p}"
  code="$(http_code "$url")"
  if [ "$code" != "200" ]; then
    err "TAB $p HTTP=$code"
    continue
  fi
  ok "TAB $p HTTP=200"

  curl -sS "$url" > "$tmp/page_${p//\//_}.html"

  # Extract JS/CSS src/href (only /static/*)
  grep -oE 'src="/static/[^"]+"' "$tmp/page_${p//\//_}.html" | sed -E 's/^src="|"$//g' >> "$tmp/all_assets.txt" || true
  grep -oE 'href="/static/[^"]+"' "$tmp/page_${p//\//_}.html" | sed -E 's/^href="|"$//g' >> "$tmp/all_assets.txt" || true

  grep -oE '/static/js/[^"]+' "$tmp/page_${p//\//_}.html" | sed 's/"$//' >> "$tmp/all_js.txt" || true
  grep -oE '/static/css/[^"]+' "$tmp/page_${p//\//_}.html" | sed 's/"$//' >> "$tmp/all_css.txt" || true

  # soft “commercial regressions” checks
  if [ "$p" = "/vsp5" ]; then
    if grep -q 'id="vsp-dashboard-main"' "$tmp/page_${p//\//_}.html"; then
      ok "Dashboard root marker present (id=vsp-dashboard-main)"
    elif grep -qi 'vsp-dashboard' "$tmp/page_${p//\//_}.html"; then
      warn "Dashboard has 'vsp-dashboard' text but missing id=vsp-dashboard-main (check blank regression?)"
    else
      warn "Dashboard root marker not detected (check template markers)"
    fi
  fi

  # ensure tab has at least 1 JS (avoid “white page due to missing assets”)
  js_count="$(grep -oE '/static/js/[^"]+' "$tmp/page_${p//\//_}.html" | wc -l | awk '{print $1}')"
  if [ "$js_count" -gt 0 ]; then ok "TAB $p js_count=$js_count"; else warn "TAB $p has no JS referenced"; fi
done

# dedupe + list assets
sort -u "$tmp/all_assets.txt" > "$tmp/assets_uniq.txt" || true
sort -u "$tmp/all_js.txt" > "$tmp/js_uniq.txt" || true
sort -u "$tmp/all_css.txt" > "$tmp/css_uniq.txt" || true

asset_total="$(wc -l < "$tmp/assets_uniq.txt" | awk '{print $1}')"
js_total="$(wc -l < "$tmp/js_uniq.txt" | awk '{print $1}')"
css_total="$(wc -l < "$tmp/css_uniq.txt" | awk '{print $1}')"
ok "assets_uniq_total=$asset_total (js=$js_total css=$css_total)"

# ---------- [B] Asset 200 OK ----------
echo | tee -a "$REPORT_TXT"
echo "== [B] Assets: JS/CSS 200 OK ==" | tee -a "$REPORT_TXT"

while IFS= read -r a; do
  [ -n "$a" ] || continue
  u="${BASE}${a}"
  code="$(http_code "$u")"
  if [ "$code" != "200" ]; then
    err "ASSET HTTP=$code $a"
  fi
done < "$tmp/assets_uniq.txt"

# If no errors in this section, mark OK
if [ "$ERR" -eq 0 ]; then ok "All referenced assets return 200"; else warn "Some assets failed (see ERR above)"; fi

# ---------- [C] Suspicious duplication check ----------
# Flag if same basename appears in multiple distinct URLs (can indicate accidental duplicates / cache bust mismatch)
echo | tee -a "$REPORT_TXT"
echo "== [C] Suspicious duplication: same basename with multiple URLs ==" | tee -a "$REPORT_TXT"

python3 - "$tmp/js_uniq.txt" "$tmp/css_uniq.txt" <<'PY' | tee "$tmp/dup_report.txt"
import sys, pathlib
from collections import defaultdict

def load(p):
    try:
        return [x.strip() for x in pathlib.Path(p).read_text(encoding="utf-8", errors="replace").splitlines() if x.strip()]
    except FileNotFoundError:
        return []

items = load(sys.argv[1]) + load(sys.argv[2])
by_base = defaultdict(set)
for u in items:
    base = u.split("?")[0].rsplit("/", 1)[-1]
    by_base[base].add(u)

dups = {b: sorted(list(urls)) for b, urls in by_base.items() if len(urls) > 1}
print(f"total_assets={len(items)}; basenames_with_multi_urls={len(dups)}")
for b, urls in sorted(dups.items(), key=lambda kv: (-len(kv[1]), kv[0]))[:80]:
    print(f"[DUP] {b} => {len(urls)} urls")
    for u in urls[:10]:
        print(f"  - {u}")
PY

dup_n="$(grep -c '^\[DUP\]' "$tmp/dup_report.txt" 2>/dev/null || echo 0)"
if [ "$dup_n" -eq 0 ]; then
  ok "No suspicious basename multi-URL duplication"
else
  warn "Found $dup_n basenames with multiple distinct URLs (review $tmp/dup_report.txt)"
fi

# ---------- [D] API contract ----------
echo | tee -a "$REPORT_TXT"
echo "== [D] API contract: rid_latest, ui_health_v2, top_findings_v1, trend_v1 ==" | tee -a "$REPORT_TXT"

# rid_latest
code="$(http_code "${BASE}/api/vsp/rid_latest")"
if [ "$code" != "200" ]; then
  err "API rid_latest HTTP=$code"
else
  curl -sS "${BASE}/api/vsp/rid_latest" > "$tmp/rid_latest.json"
  python3 - "$tmp/rid_latest.json" <<'PY' || { err "API rid_latest contract FAIL"; }
import json,sys,re
j=json.load(open(sys.argv[1],"r",encoding="utf-8"))
if j.get("ok") is not True: raise SystemExit(2)
rid=j.get("rid") or ""
if not rid.strip(): raise SystemExit(2)
# accept both VSP_CI_* and RUN_* (but prefer deduped VSP_CI_*)
print("rid=",rid)
PY
  ok "API rid_latest contract OK"
fi

# ui_health_v2
code="$(http_code "${BASE}/api/vsp/ui_health_v2")"
if [ "$code" != "200" ]; then
  err "API ui_health_v2 HTTP=$code"
else
  curl -sS "${BASE}/api/vsp/ui_health_v2" > "$tmp/ui_health_v2.json"
  python3 - "$tmp/ui_health_v2.json" <<'PY' || { err "API ui_health_v2 contract FAIL"; }
import json,sys
j=json.load(open(sys.argv[1],"r",encoding="utf-8"))
if j.get("ok") is not True: raise SystemExit(2)
# marker is optional but "commercial clean" expects it often exists
m=j.get("marker")
if m is None:
    print("marker=(missing)")
else:
    print("marker=",m)
PY
  ok "API ui_health_v2 contract OK"
fi

# top_findings_v1
code="$(http_code "${BASE}/api/vsp/top_findings_v1?limit=8")"
if [ "$code" != "200" ]; then
  err "API top_findings_v1 HTTP=$code"
else
  curl -sS "${BASE}/api/vsp/top_findings_v1?limit=8" > "$tmp/top_findings_v1.json"
  python3 - "$tmp/top_findings_v1.json" <<'PY' || { err "API top_findings_v1 contract FAIL"; }
import json,sys
j=json.load(open(sys.argv[1],"r",encoding="utf-8"))
if j.get("ok") is not True: raise SystemExit(2)
items=j.get("items") or []
total=j.get("total")
run_id=j.get("run_id")
if run_id is None: raise SystemExit(2)
if total is None: raise SystemExit(2)
print("run_id=",run_id," total=",total," items_len=",len(items))
PY
  ok "API top_findings_v1 contract OK"
fi

# trend_v1
code="$(http_code "${BASE}/api/vsp/trend_v1")"
if [ "$code" != "200" ]; then
  err "API trend_v1 HTTP=$code"
else
  curl -sS "${BASE}/api/vsp/trend_v1" > "$tmp/trend_v1.json"
  python3 - "$tmp/trend_v1.json" <<'PY' || { err "API trend_v1 contract FAIL"; }
import json,sys
j=json.load(open(sys.argv[1],"r",encoding="utf-8"))
if j.get("ok") is not True: raise SystemExit(2)
pts=j.get("points") or []
marker=j.get("marker")
print("marker=",marker)
if not isinstance(pts,list): raise SystemExit(2)
if len(pts)==0:
    # allow empty trend but warn at shell level by printing a tag
    print("[EMPTY_POINTS]")
else:
    p0=pts[0] or {}
    for k in ("label","run_id","total","ts"):
        if k not in p0: raise SystemExit(2)
    print("first_point=", {k:p0.get(k) for k in ("label","run_id","total","ts")})
PY
  if grep -q '\[EMPTY_POINTS\]' "$tmp/trend_v1.json" 2>/dev/null; then
    warn "API trend_v1 points empty (OK contract but check data ingestion)"
  else
    ok "API trend_v1 contract OK"
  fi
fi

# ---------- [E] Patch markers density (optional beauty) ----------
echo | tee -a "$REPORT_TXT"
echo "== [E] Patch markers scan (optional cleanup) ==" | tee -a "$REPORT_TXT"

W="wsgi_vsp_ui_gateway.py"
if [ -f "$W" ]; then
  marker_count="$(grep -oE 'VSP_[A-Z0-9_]{6,}' "$W" | sort -u | wc -l | awk '{print $1}')"
  ok "wsgi markers unique_count=$marker_count"
  tail_markers="$(tail -n 260 "$W" | grep -oE 'VSP_[A-Z0-9_]{6,}' | sort -u | head -n 60 || true)"
  if [ -n "$tail_markers" ]; then
    echo "tail_markers(sample):" | tee -a "$REPORT_TXT"
    echo "$tail_markers" | sed 's/^/  - /' | tee -a "$REPORT_TXT"
  fi
else
  warn "missing $W (skip markers scan)"
fi

# ---------- [F] Log hygiene ----------
err_after="$(get_file_size "$ERRLOG")"
delta=$((err_after - err_before))
echo | tee -a "$REPORT_TXT"
echo "== [F] Log hygiene ==" | tee -a "$REPORT_TXT"
echo "errlog_size_after=$err_after bytes (delta=$delta)" | tee -a "$REPORT_TXT"

if [ "$delta" -gt 0 ]; then
  warn "Error log grew by $delta bytes during audit (check ERRLOG; consider rotate)"
else
  ok "No error-log growth during audit"
fi

# size warning threshold (50MB)
if [ "$err_after" -gt $((50*1024*1024)) ]; then
  warn "ERRLOG > 50MB (consider rotate): $ERRLOG"
else
  ok "ERRLOG size within threshold"
fi

# ---------- [G] Save JSON summary ----------
python3 - <<PY > "$REPORT_JSON"
import json, os, time
d = {
  "ts": "$ts",
  "base": "$BASE",
  "service": "$SVC",
  "errlog": "$ERRLOG",
  "counts": {"ok": $OK, "warn": $WARN, "err": $ERR},
  "artifacts": {
    "report_txt": "$REPORT_TXT",
    "assets_uniq": "$tmp/assets_uniq.txt",
    "js_uniq": "$tmp/js_uniq.txt",
    "css_uniq": "$tmp/css_uniq.txt",
    "api_payloads_dir": "$tmp",
  }
}
print(json.dumps(d, indent=2, ensure_ascii=False))
PY
ok "Saved audit report: $REPORT_TXT"
ok "Saved audit json:   $REPORT_JSON"

echo | tee -a "$REPORT_TXT"
echo "== SUMMARY ==" | tee -a "$REPORT_TXT"
echo "OK=$OK WARN=$WARN ERR=$ERR" | tee -a "$REPORT_TXT"

if [ "$ERR" -gt 0 ]; then
  echo "[FAIL] commercial final audit has ERR" | tee -a "$REPORT_TXT"
  exit 1
fi
echo "[PASS] commercial final audit OK (WARN=$WARN)" | tee -a "$REPORT_TXT"
exit 0
