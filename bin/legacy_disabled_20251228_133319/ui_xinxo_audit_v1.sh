#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TMP="$(mktemp -d /tmp/vsp_ui_xinxo_audit_XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need sed; need awk; need sort; need uniq; need wc; need head; need python3; need date

ts(){ date +"%Y-%m-%d %H:%M:%S"; }
hr(){ printf '%*s\n' 110 | tr ' ' '-'; }

PAGES=(/vsp5 /runs /data_source /settings /rule_overrides)

# Required markers (gate-ish)
declare -A REQ
REQ[/vsp5]='vsp|dashboard|kpi|trend|top'
REQ[/runs]='runs|report|rid|run'
REQ[/data_source]='data|source|findings|unified'
REQ[/settings]='settings|config|tool'
REQ[/rule_overrides]='rule|override|editor|apply'

# Optional “xịn xò” markers
declare -A OPT
OPT[/vsp5]='posture|score|trend|chart|top_findings|severity|donut|spark|skeleton|data-testid'
OPT[/runs]='filter|search|date|range|severity|tool|export|pdf|html|zip|drill|paging|sort|data-testid'
OPT[/data_source]='search|filter|query|table|paging|sort|copy|sarif|json|file path|data-testid'
OPT[/settings]='toggle|profile|validate|explain|iso|mapping|policy|data-testid'
OPT[/rule_overrides]='editor|textarea|diff|apply|preview|audit|log|history|data-testid'

# API checks (contract-ish)
API_LIST=(
  "/api/vsp/rid_latest"
  "/api/vsp/runs?limit=5&offset=0"
  "/api/vsp/trend_v1"
  "/api/vsp/top_findings_v1?limit=5"
  "/api/vsp/release_latest"
)

echo "VSP UI XINXO AUDIT v1  @ $(ts)"
echo "BASE=$BASE"
hr

echo "== [A] API contract quick-check =="
for ep in "${API_LIST[@]}"; do
  out="$TMP/api_$(echo "$ep" | sed 's#[/?=&]#_#g').json"
  if curl -fsS "$BASE$ep" -o "$out" 2>/dev/null; then
    python3 - "$ep" "$out" <<'PY'
import json, sys
ep, path = sys.argv[1], sys.argv[2]
try:
  j=json.load(open(path,'r',encoding='utf-8'))
except Exception as e:
  print(f"[FAIL] {ep}: invalid json: {e}")
  raise SystemExit(0)

def has(k): return k in j and j[k] not in (None, "", [], {})
ok = j.get("ok", True)  # many endpoints don't include ok
msg=[]
status="OK"
if ep.endswith("/api/vsp/rid_latest"):
  if not has("rid"): status="WARN"; msg.append("missing rid")
elif "/api/vsp/runs" in ep:
  if not has("runs"): status="WARN"; msg.append("missing runs[]")
elif ep.endswith("/api/vsp/trend_v1"):
  if not has("points"): status="WARN"; msg.append("missing points[]")
elif ep.startswith("/api/vsp/top_findings_v1"):
  # allow empty items; but key should exist
  if "items" not in j: status="WARN"; msg.append("missing items[]")
elif ep.endswith("/api/vsp/release_latest"):
  # accept either url-based or path-based contract
  keys = set(j.keys())
  good = any(k in keys for k in ["download_url","package_url","package_path","download_path"])
  if not good:
    status="WARN"; msg.append("missing download/package link/path")
  if not any(k in keys for k in ["sha256","package_sha256","sha256sum"]):
    status="WARN"; msg.append("missing sha256 field")
print(f"[{status}] {ep} keys=" + ",".join(sorted(list(j.keys()))[:18]) + (" ..." if len(j.keys())>18 else "") + ("" if not msg else " | " + "; ".join(msg)))
PY
  else
    echo "[FAIL] $ep (curl failed)"
  fi
done
hr

echo "== [B] Fetch HTML per tab + extract assets =="
ALL_ASSETS="$TMP/all_assets.txt"
: > "$ALL_ASSETS"

for P in "${PAGES[@]}"; do
  fn="$TMP/page_$(echo "$P" | tr '/' '_' ).html"
  if ! curl -fsS "$BASE$P" -o "$fn"; then
    echo "[FAIL] $P: cannot fetch HTML"
    continue
  fi

  js="$TMP/$(echo "$P" | tr '/' '_' )_js.txt"
  css="$TMP/$(echo "$P" | tr '/' '_' )_css.txt"

  # Extract /static assets referenced in HTML
  grep -oE '/static/js/[^"'\'' >]+' "$fn" | sed 's/[?].*$//' | sort -u > "$js" || true
  grep -oE '/static/css/[^"'\'' >]+' "$fn" | sed 's/[?].*$//' | sort -u > "$css" || true

  cat "$js" "$css" >> "$ALL_ASSETS"

  echo "-- $P --"
  echo "HTML: $fn  (bytes=$(wc -c <"$fn" | tr -d ' '))"
  echo "JS:  $(wc -l <"$js" | tr -d ' ') files"
  echo "CSS: $(wc -l <"$css" | tr -d ' ') files"
done
hr

echo "== [C] Duplicate asset detection (global) =="
sort "$ALL_ASSETS" | sed '/^$/d' | uniq -c | awk '$1>1{print}' | head -n 60 || true
hr

echo "== [D] Per-tab marker checks (REQ=must, OPT=nice) =="
printf "%-16s | %-6s | %-8s | %-8s | %-10s | %-10s | %s\n" "TAB" "FETCH" "REQ_OK" "OPT_HIT" "JS_COUNT" "CSS_COUNT" "NOTES"
hr

for P in "${PAGES[@]}"; do
  fn="$TMP/page_$(echo "$P" | tr '/' '_' ).html"
  js="$TMP/$(echo "$P" | tr '/' '_' )_js.txt"
  css="$TMP/$(echo "$P" | tr '/' '_' )_css.txt"

  if [ ! -f "$fn" ]; then
    printf "%-16s | %-6s | %-8s | %-8s | %-10s | %-10s | %s\n" "$P" "FAIL" "n/a" "n/a" "0" "0" "no HTML"
    continue
  fi

  # Simple content scan: HTML + first 1200 lines of each referenced JS (avoid huge)
  scan="$TMP/scan_$(echo "$P" | tr '/' '_' ).txt"
  : > "$scan"
  cat "$fn" > "$scan"
  while read -r a; do
    # fetch JS content to scan keywords quickly (best-effort)
    if [[ "$a" == /static/js/* ]]; then
      curl -fsS "$BASE$a" 2>/dev/null | head -n 1200 >> "$scan" || true
    fi
  done < "$js"

  req_pat="${REQ[$P]}"
  opt_pat="${OPT[$P]}"

  # Required: if any token hits
  req_ok="FAIL"
  if echo "$req_pat" | tr '|' '\n' | while read -r k; do grep -qiE "$k" "$scan" && echo HIT && break || true; done | grep -q HIT; then
    req_ok="OK"
  fi

  # Optional: count hits (unique tokens)
  opt_hit=0
  while read -r k; do
    if grep -qiE "$k" "$scan"; then opt_hit=$((opt_hit+1)); fi
  done < <(echo "$opt_pat" | tr '|' '\n')

  jsn=$(wc -l <"$js" | tr -d ' ' 2>/dev/null || echo 0)
  cssn=$(wc -l <"$css" | tr -d ' ' 2>/dev/null || echo 0)

  notes=()
  if grep -RqiE 'TODO|FIXME|DEBUG' "$scan"; then notes+=("has TODO/FIXME/DEBUG"); fi
  if grep -RqiE 'N/A' "$scan"; then notes+=("has N/A"); fi
  if grep -RqiE 'kc_idp_hint|realms/|keycloak' "$scan"; then notes+=("auth strings present"); fi

  # Per-tab duplicate CSS reference (same file appears more than once in HTML)
  dup_css=$(grep -oE '/static/css/[^"'\'' >]+' "$fn" | sed 's/[?].*$//' | sort | uniq -c | awk '$1>1{print $2}' | head -n 3 | tr '\n' ',' | sed 's/,$//')
  if [ -n "${dup_css:-}" ]; then notes+=("dup_css:${dup_css}"); fi

  printf "%-16s | %-6s | %-8s | %-8s | %-10s | %-10s | %s\n" \
    "$P" "OK" "$req_ok" "$opt_hit" "$jsn" "$cssn" "$(IFS='; '; echo "${notes[*]:-}")"
done
hr

echo "== [E] Quick “xịn xò readiness” score (rough) =="
python3 - "$TMP" <<'PY'
import os, glob, re
tmp=sys.argv[1]
pages=["_vsp5","_runs","_data_source","_settings","_rule_overrides"]
rows=[]
for p in pages:
  scan=glob.glob(os.path.join(tmp,f"scan{p}*.txt"))
  if not scan: 
    rows.append((p,0,0,0)); 
    continue
  s=open(scan[0],'r',encoding='utf-8',errors='ignore').read()
  # heuristics
  has_testid = 1 if re.search(r"data-testid", s, re.I) else 0
  has_export  = 1 if re.search(r"\b(export|pdf|html|zip)\b", s, re.I) else 0
  has_filters = 1 if re.search(r"\b(filter|search|query|date range|severity|tool)\b", s, re.I) else 0
  rows.append((p,has_testid,has_export,has_filters))

print("TAB              testid export filters")
for p,a,b,c in rows:
  print(f"{p:16} {a:6} {b:6} {c:7}")
PY
hr

echo "== [F] Suggested next 3 patches (auto from missing signals) =="
echo "1) Dashboard (/vsp5): add real widgets (KPI strip + posture score + trend chart + top findings table) + data-testid hooks."
echo "2) Runs (/runs): add filters (RID/date/tool/sev) + export hooks (HTML/PDF/ZIP) + sortable/paging table."
echo "3) Data Source (/data_source): add search/filter + deep-dive row drawer (copy SARIF/JSON, file path open/copy)."
echo
echo "[DONE] Artifacts in: $TMP (auto-clean on exit). Re-run to regenerate."
