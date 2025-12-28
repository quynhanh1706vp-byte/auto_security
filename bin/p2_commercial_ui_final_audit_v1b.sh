#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
ERRLOG="${VSP_UI_ERRLOG:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log}"
KEEP_TMP_ON_FAIL="${VSP_AUDIT_KEEP_TMP_ON_FAIL:-1}"   # 1=keep on fail; 0=delete always

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need head; need sort; need uniq; need wc; need date; need mktemp; need stat

OK=0; WARN=0; ERR=0
ok(){ echo "[OK]   $*"; OK=$((OK+1)); }
warn(){ echo "[WARN] $*"; WARN=$((WARN+1)); }
err(){ echo "[ERR]  $*"; ERR=$((ERR+1)); }

ts="$(date +%Y%m%d_%H%M%S)"
tmp="$(mktemp -d /tmp/vsp_final_audit_${ts}_XXXXXX)"

OUTDIR="out_ci"
mkdir -p "$OUTDIR"
REPORT_TXT="${OUTDIR}/final_audit_${ts}.txt"
REPORT_JSON="${OUTDIR}/final_audit_${ts}.json"
PAYLOAD_DIR="${OUTDIR}/final_audit_${ts}_payloads"
mkdir -p "$PAYLOAD_DIR"

cleanup(){
  if [ "$ERR" -gt 0 ] && [ "$KEEP_TMP_ON_FAIL" = "1" ]; then
    warn "keeping tmp dir for inspection: $tmp"
    cp -a "$tmp" "$PAYLOAD_DIR/tmp_copy" 2>/dev/null || true
  fi
  rm -rf "$tmp" 2>/dev/null || true
}
trap cleanup EXIT

http_code(){
  curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 10 "$1" || echo "000"
}

get_file_size(){
  local f="$1"
  if [ -f "$f" ]; then stat -c%s "$f" 2>/dev/null || wc -c <"$f" 2>/dev/null || echo 0
  else echo 0
  fi
}

get_file_lines(){
  local f="$1"
  if [ -f "$f" ]; then wc -l <"$f" 2>/dev/null || echo 0
  else echo 0
  fi
}

api_check(){
  # usage: api_check name url python_code_string
  local name="$1" url="$2" py="$3"
  local code
  code="$(http_code "$url")"
  if [ "$code" != "200" ]; then
    err "API $name HTTP=$code url=$url"
    return 0
  fi
  curl -sS "$url" > "$tmp/${name}.json" || true
  cp -f "$tmp/${name}.json" "$PAYLOAD_DIR/${name}.json" 2>/dev/null || true

  python3 - "$tmp/${name}.json" <<PY
import json,sys
p=sys.argv[1]
try:
  j=json.load(open(p,"r",encoding="utf-8"))
except Exception as e:
  print(f"[PY_ERR] invalid JSON: {e}")
  raise SystemExit(2)

if j.get("ok") is not True:
  print(f"[PY_ERR] ok!=true (ok={j.get('ok')})")
  raise SystemExit(2)

$py
print("[PY_OK]")
PY
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "API $name contract OK"
  else
    err "API $name contract FAIL (see $PAYLOAD_DIR/${name}.json)"
  fi
}

{
echo "== VSP Commercial Final Audit (v1b) =="
echo "ts=$ts"
echo "BASE=$BASE"
echo "SVC=$SVC"
echo "ERRLOG=$ERRLOG"
echo "PAYLOAD_DIR=$PAYLOAD_DIR"
echo
} | tee "$REPORT_TXT"

# service status (best effort)
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet "$SVC"; then ok "systemd $SVC active"; else warn "systemd $SVC not active (or not found)"; fi
else
  warn "systemctl not found; skip service check"
fi

# log baseline
err_before="$(get_file_size "$ERRLOG")"
lines_before="$(get_file_lines "$ERRLOG")"
ok "errlog_size_before=$err_before bytes"
ok "errlog_lines_before=$lines_before"

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

  if [ "$p" = "/vsp5" ]; then
    if grep -q 'id="vsp-dashboard-main"' "$tmp/page_${p//\//_}.html"; then
      ok "Dashboard root marker present (id=vsp-dashboard-main)"
    else
      warn "Dashboard root marker missing (id=vsp-dashboard-main) — check blank regression"
    fi
  fi

  js_count="$(grep -oE '/static/js/[^"]+' "$tmp/page_${p//\//_}.html" | wc -l | awk '{print $1}')"
  if [ "$js_count" -gt 0 ]; then ok "TAB $p js_count=$js_count"; else warn "TAB $p has no JS referenced"; fi
done

sort -u "$tmp/all_assets.txt" > "$tmp/assets_uniq.txt" || true
sort -u "$tmp/all_js.txt" > "$tmp/js_uniq.txt" || true
sort -u "$tmp/all_css.txt" > "$tmp/css_uniq.txt" || true

asset_total="$(wc -l < "$tmp/assets_uniq.txt" | awk '{print $1}')"
js_total="$(wc -l < "$tmp/js_uniq.txt" | awk '{print $1}')"
css_total="$(wc -l < "$tmp/css_uniq.txt" | awk '{print $1}')"
ok "assets_uniq_total=$asset_total (js=$js_total css=$css_total)"

cp -f "$tmp/assets_uniq.txt" "$PAYLOAD_DIR/assets_uniq.txt" 2>/dev/null || true
cp -f "$tmp/js_uniq.txt" "$PAYLOAD_DIR/js_uniq.txt" 2>/dev/null || true
cp -f "$tmp/css_uniq.txt" "$PAYLOAD_DIR/css_uniq.txt" 2>/dev/null || true

# ---------- [B] Asset 200 OK ----------
echo | tee -a "$REPORT_TXT"
echo "== [B] Assets: JS/CSS 200 OK ==" | tee -a "$REPORT_TXT"

asset_err_before="$ERR"
while IFS= read -r a; do
  [ -n "$a" ] || continue
  u="${BASE}${a}"
  code="$(http_code "$u")"
  if [ "$code" != "200" ]; then
    err "ASSET HTTP=$code $a"
  fi
done < "$tmp/assets_uniq.txt"

if [ "$ERR" -eq "$asset_err_before" ]; then ok "All referenced assets return 200"; else warn "Some assets failed"; fi

# ---------- [C] Dup basename / multi URL ----------
echo | tee -a "$REPORT_TXT"
echo "== [C] Suspicious duplication: same basename with multiple URLs ==" | tee -a "$REPORT_TXT"

python3 - "$tmp/js_uniq.txt" "$tmp/css_uniq.txt" <<'PY' | tee "$PAYLOAD_DIR/dup_report.txt"
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
for b, urls in sorted(dups.items(), key=lambda kv: (-len(kv[1]), kv[0]))[:200]:
    print(f"[DUP] {b} => {len(urls)} urls")
    for u in urls:
        print(f"  - {u}")
PY

dup_n="$(grep -c '^\[DUP\]' "$PAYLOAD_DIR/dup_report.txt" 2>/dev/null || echo 0)"
if [ "$dup_n" -eq 0 ]; then
  ok "No suspicious basename multi-URL duplication"
else
  warn "Found $dup_n basenames with multiple distinct URLs (usually asset_v differs across tabs). See $PAYLOAD_DIR/dup_report.txt"
fi

# ---------- [D] API contract ----------
echo | tee -a "$REPORT_TXT"
echo "== [D] API contract ==" | tee -a "$REPORT_TXT"

api_check "rid_latest"      "${BASE}/api/vsp/rid_latest"        $'rid=j.get("rid") or ""\nif not rid.strip(): raise SystemExit(2)\nprint("rid=",rid)'
api_check "ui_health_v2"    "${BASE}/api/vsp/ui_health_v2"      $'print("marker=", j.get("marker"))'
api_check "top_findings_v1" "${BASE}/api/vsp/top_findings_v1?limit=8" $'items=j.get("items")\nif items is None: raise SystemExit(2)\nif not isinstance(items,list): raise SystemExit(2)\nif j.get("run_id") is None: raise SystemExit(2)\nif j.get("total") is None: raise SystemExit(2)\nprint("run_id=",j.get("run_id")," total=",j.get("total")," items_len=",len(items))'
api_check "trend_v1"        "${BASE}/api/vsp/trend_v1"          $'pts=j.get("points")\nif pts is None or not isinstance(pts,list): raise SystemExit(2)\nprint("marker=", j.get("marker"))\nprint("points_len=", len(pts))\nif len(pts)>0:\n  p0=pts[0] or {}\n  for k in ("label","run_id","total","ts"):\n    if k not in p0: raise SystemExit(2)\n  print("first_point=", {k:p0.get(k) for k in ("label","run_id","total","ts")})'

# ---------- [E] Patch markers density (optional beauty) ----------
echo | tee -a "$REPORT_TXT"
echo "== [E] Patch markers scan (optional cleanup) ==" | tee -a "$REPORT_TXT"

W="wsgi_vsp_ui_gateway.py"
if [ -f "$W" ]; then
  marker_count="$(grep -oE 'VSP_[A-Z0-9_]{6,}' "$W" | sort -u | wc -l | awk '{print $1}')"
  ok "wsgi markers unique_count=$marker_count"
else
  warn "missing $W (skip markers scan)"
fi

# ---------- [F] Log hygiene ----------
err_after="$(get_file_size "$ERRLOG")"
lines_after="$(get_file_lines "$ERRLOG")"
delta=$((err_after - err_before))
new_lines=$((lines_after - lines_before))

echo | tee -a "$REPORT_TXT"
echo "== [F] Log hygiene ==" | tee -a "$REPORT_TXT"
echo "errlog_size_after=$err_after bytes (delta=$delta)" | tee -a "$REPORT_TXT"
echo "errlog_lines_after=$lines_after (new_lines=$new_lines)" | tee -a "$REPORT_TXT"

if [ "$new_lines" -gt 0 ] && [ -f "$ERRLOG" ]; then
  warn "New errlog lines detected; dumping appended lines:"
  sed -n "$((lines_before+1)),\$p" "$ERRLOG" | tail -n 120 | sed 's/^/[ERRLOG+] /' | tee -a "$REPORT_TXT" || true
else
  ok "No new errlog lines during audit"
fi

# ---------- [G] Save JSON summary ----------
python3 - <<PY > "$REPORT_JSON"
import json
d = {
  "ts": "$ts",
  "base": "$BASE",
  "service": "$SVC",
  "errlog": "$ERRLOG",
  "payload_dir": "$PAYLOAD_DIR",
  "counts": {"ok": $OK, "warn": $WARN, "err": $ERR},
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
