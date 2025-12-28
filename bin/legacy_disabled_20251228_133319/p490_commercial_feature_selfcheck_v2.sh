#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p490v2_feature_${TS}"
mkdir -p "$OUT/js" "$OUT/html" "$OUT/api" "$OUT/logs"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/logs/run.log"; exit 2; }; }
need curl; need python3; need awk; need sed; need grep; need date
TO="$(command -v timeout || true)"

ok(){ echo "[OK] $*" | tee -a "$OUT/logs/run.log"; }
warn(){ echo "[WARN] $*" | tee -a "$OUT/logs/run.log"; }
fail(){ echo "[FAIL] $*" | tee -a "$OUT/logs/run.log"; }

tabs=(/c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)

echo "== [P490v2] BASE=$BASE TS=$TS ==" | tee "$OUT/SUMMARY.txt"

# 1) Fetch HTML + headers
rel_ts=""; rel_sha=""
for p in "${tabs[@]}"; do
  fhtml="$OUT/html/$(echo "$p" | tr '/?' '__').html"
  fhdr="$OUT/html/$(echo "$p" | tr '/?' '__').hdr"
  if [ -n "$TO" ]; then
    $TO 8s curl -sS -D "$fhdr" "$BASE$p" -o "$fhtml" || { fail "fetch $p"; continue; }
  else
    curl -sS -D "$fhdr" "$BASE$p" -o "$fhtml" || { fail "fetch $p"; continue; }
  fi

  code="$(awk 'BEGIN{IGNORECASE=1} /^HTTP\//{print $2; exit}' "$fhdr" || true)"
  ct="$(awk 'BEGIN{IGNORECASE=1} /^Content-Type:/{sub("\r",""); print $0}' "$fhdr" || true)"
  len="$(awk 'BEGIN{IGNORECASE=1} /^Content-Length:/{gsub("\r",""); print $2}' "$fhdr" || true)"
  rts="$(awk 'BEGIN{IGNORECASE=1} /^X-VSP-RELEASE-TS:/{gsub("\r",""); print $2}' "$fhdr" || true)"
  rsha="$(awk 'BEGIN{IGNORECASE=1} /^X-VSP-RELEASE-SHA:/{gsub("\r",""); print $2}' "$fhdr" || true)"

  echo "" >> "$OUT/SUMMARY.txt"
  echo "== TAB $p ==" >> "$OUT/SUMMARY.txt"
  echo "http=$code" >> "$OUT/SUMMARY.txt"
  echo "$ct" >> "$OUT/SUMMARY.txt"
  echo "Content-Length=${len:-?}" >> "$OUT/SUMMARY.txt"
  echo "X-VSP-RELEASE-TS=${rts:-?}" >> "$OUT/SUMMARY.txt"
  echo "X-VSP-RELEASE-SHA=${rsha:-?}" >> "$OUT/SUMMARY.txt"

  [ "${code:-}" = "200" ] || warn "$p HTTP=$code"
  [ -z "$rel_ts" ] && [ -n "$rts" ] && rel_ts="$rts"
  [ -z "$rel_sha" ] && [ -n "$rsha" ] && rel_sha="$rsha"
done

echo "" >> "$OUT/SUMMARY.txt"
echo "== RELEASE CONSISTENCY ==" >> "$OUT/SUMMARY.txt"
echo "TS=$rel_ts" >> "$OUT/SUMMARY.txt"
echo "SHA=$rel_sha" >> "$OUT/SUMMARY.txt"

# 2) Extract JS URLs + download
js_list="$OUT/js_urls.txt"
: > "$js_list"
for p in "${tabs[@]}"; do
  fhtml="$OUT/html/$(echo "$p" | tr '/?' '__').html"
  grep -Eo 'src="[^"]+\.js[^"]*"' "$fhtml" | sed -E 's/^src="//; s/"$//' >> "$js_list" || true
done
python3 - <<'PY' "$js_list" > "$OUT/js_urls_dedup.txt"
import sys
p=sys.argv[1]
seen=[]
for line in open(p,encoding="utf-8",errors="replace"):
    u=line.strip()
    if u and u not in seen:
        seen.append(u)
for u in seen:
    print(u)
PY
mv -f "$OUT/js_urls_dedup.txt" "$js_list"
echo "" >> "$OUT/SUMMARY.txt"
echo "== JS URLS ==" >> "$OUT/SUMMARY.txt"
echo "count=$(wc -l < "$js_list" | tr -d ' ') (download to $OUT/js)" >> "$OUT/SUMMARY.txt"

i=0
while IFS= read -r u; do
  i=$((i+1))
  [[ "$u" == http* ]] || u="$BASE${u}"
  fn="$OUT/js/js_${i}.js"
  if [ -n "$TO" ]; then $TO 10s curl -sS "$u" -o "$fn" || true; else curl -sS "$u" -o "$fn" || true; fi
done < "$js_list"

# 3) Discover /api/... from JS
api_list="$OUT/apis_found.txt"
: > "$api_list"
grep -RhoE '(["'\'']\/api\/[^"'\'' ]+)' "$OUT/js" 2>/dev/null \
  | sed -E 's/^["'\'']//; s/["'\'']$//' \
  | sed -E 's/[);,]+$//' \
  | grep -E '^/api/' >> "$api_list" || true

python3 - <<'PY' "$api_list" > "$OUT/apis_found_dedup.txt"
import sys
p=sys.argv[1]
seen=[]
for line in open(p,encoding="utf-8",errors="replace"):
    u=line.strip()
    if u and u not in seen:
        seen.append(u)
for u in seen:
    print(u)
PY
mv -f "$OUT/apis_found_dedup.txt" "$api_list"
echo "" >> "$OUT/SUMMARY.txt"
echo "== API DISCOVERY ==" >> "$OUT/SUMMARY.txt"
echo "found=$(wc -l < "$api_list" | tr -d ' ') (from JS grep)" >> "$OUT/SUMMARY.txt"

# 4) Get RID from runs_v3 (fast) and use it to normalize probes
RID="$(
  curl -fsS "$BASE/api/vsp/runs_v3?limit=5&include_ci=1" \
  | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
rid=""
for k in ("rid",):
    if isinstance(j,dict) and j.get(k): rid=j.get(k)
if not rid and isinstance(j,dict):
    for arrk in ("items","runs"):
        arr=j.get(arrk) or []
        if isinstance(arr,list) and arr and isinstance(arr[0],dict) and arr[0].get("rid"):
            rid=arr[0]["rid"]; break
print(rid or "")
PY
)"
echo "" >> "$OUT/SUMMARY.txt"
echo "== RID ==" >> "$OUT/SUMMARY.txt"
echo "RID=${RID:-<empty>}" >> "$OUT/SUMMARY.txt"

echo "path,http,time_total,is_json,keys_or_len" > "$OUT/apis_probe.csv"

need_rid_re='/(datasource_v3|data_source_v1|findings_unified_v1|exports_v1|overrides_v1|run_status_v1|dashboard_kpis_v4)$'

normalize_path(){
  local path="$1"

  # rewrite old runs -> runs_v3 (giống commercial fetch patch)
  if [[ "$path" == /api/vsp/runs\?* ]] || [[ "$path" == /api/vsp/runs$* ]]; then
    path="${path/\/api\/vsp\/runs/\/api\/vsp\/runs_v3}"
  fi

  # rid= empty => fill
  if [[ "$path" == *"rid="* ]]; then
    path="$(echo "$path" | sed -E "s/rid=(&|$)/rid=${RID}\1/g")"
  fi

  # nếu cần rid mà chưa có rid= thì append
  if echo "$path" | grep -Eq "$need_rid_re" && ! echo "$path" | grep -q "rid="; then
    if [[ "$path" == *"?"* ]]; then
      path="${path}&rid=${RID}"
    else
      path="${path}?rid=${RID}"
    fi
  fi
  echo "$path"
}

probe_one(){
  local raw="$1"
  local path
  path="$(normalize_path "$raw")"
  local url="$BASE$path"
  local tmp="$OUT/api/$(echo "$path" | tr '/?&=' '____').resp"
  local hdr="$OUT/api/$(echo "$path" | tr '/?&=' '____').hdr"

  local cmd=(curl -sS -D "$hdr" -o "$tmp" -w "time_total=%{time_total}\n" "$url")
  local time_total=""
  if [ -n "$TO" ]; then
    time_total="$($TO 10s "${cmd[@]}" 2>/dev/null | tail -n1 | awk -F= '{print $2}' || true)"
  else
    time_total="$("${cmd[@]}" 2>/dev/null | tail -n1 | awk -F= '{print $2}' || true)"
  fi
  local code="$(awk 'BEGIN{IGNORECASE=1} /^HTTP\//{print $2; exit}' "$hdr" 2>/dev/null || true)"
  local ct="$(awk 'BEGIN{IGNORECASE=1} /^Content-Type:/{sub("\r",""); print $2}' "$hdr" 2>/dev/null | head -n1 || true)"

  local is_json="0"
  local keys="len=$(wc -c < "$tmp" | tr -d ' ')"
  if echo "${ct:-}" | grep -qi 'application/json'; then
    is_json="1"
    keys="$(python3 - <<'PY' "$tmp" 2>/dev/null || echo "json_parse_fail"
import sys, json
p=sys.argv[1]
j=json.load(open(p,'r',encoding='utf-8',errors='replace'))
if isinstance(j, dict):
    print("keys=" + ",".join(sorted(j.keys())[:25]))
elif isinstance(j, list):
    print("list_len=" + str(len(j)))
else:
    print("type=" + type(j).__name__)
PY
)"
  fi

  echo "$path,$code,${time_total:-},$is_json,$keys" >> "$OUT/apis_probe.csv"
}

# Probe up to 25 endpoints
n=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  n=$((n+1))
  probe_one "$path" || true
  [ "$n" -ge 25 ] && break
done < "$api_list"

ok "done: $OUT"
echo "[DONE] OUT=$OUT"
