#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p490v2b_feature_${TS}"
mkdir -p "$OUT/js" "$OUT/html" "$OUT/api" "$OUT/logs"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/logs/run.log"; exit 2; }; }
need curl; need python3; need awk; need sed; need grep; need date; need head; need wc; need tr
TO="$(command -v timeout || true)"

log(){ echo "$*" | tee -a "$OUT/logs/run.log"; }
ok(){ log "[OK] $*"; }
warn(){ log "[WARN] $*"; }

tabs=(/c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)

log "== [P490v2b] BASE=$BASE TS=$TS =="

# 1) fetch HTML + headers
rel_ts=""; rel_sha=""
for p in "${tabs[@]}"; do
  fhtml="$OUT/html/$(echo "$p" | tr '/?' '__').html"
  fhdr="$OUT/html/$(echo "$p" | tr '/?' '__').hdr"
  if [ -n "$TO" ]; then
    $TO 8s curl -sS -D "$fhdr" "$BASE$p" -o "$fhtml" || { warn "fetch $p failed"; continue; }
  else
    curl -sS -D "$fhdr" "$BASE$p" -o "$fhtml" || { warn "fetch $p failed"; continue; }
  fi

  code="$(awk 'BEGIN{IGNORECASE=1} /^HTTP\//{print $2; exit}' "$fhdr" 2>/dev/null || true)"
  len="$(awk 'BEGIN{IGNORECASE=1} /^Content-Length:/{gsub("\r",""); print $2}' "$fhdr" 2>/dev/null || true)"
  rts="$(awk 'BEGIN{IGNORECASE=1} /^X-VSP-RELEASE-TS:/{gsub("\r",""); print $2}' "$fhdr" 2>/dev/null || true)"
  rsha="$(awk 'BEGIN{IGNORECASE=1} /^X-VSP-RELEASE-SHA:/{gsub("\r",""); print $2}' "$fhdr" 2>/dev/null || true)"

  log "TAB $p http=$code len=${len:-?} rel_ts=${rts:-?}"
  [ -z "$rel_ts" ] && [ -n "$rts" ] && rel_ts="$rts"
  [ -z "$rel_sha" ] && [ -n "$rsha" ] && rel_sha="$rsha"
done
log "RELEASE TS=$rel_ts SHA=$rel_sha"

# 2) extract JS urls + download
js_list="$OUT/js_urls.txt"
: > "$js_list"
for p in "${tabs[@]}"; do
  fhtml="$OUT/html/$(echo "$p" | tr '/?' '__').html"
  [ -f "$fhtml" ] || continue
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
ok "js_count=$(wc -l < "$js_list" | tr -d ' ')"

i=0
while IFS= read -r u; do
  [ -n "$u" ] || continue
  i=$((i+1))
  [[ "$u" == http* ]] || u="$BASE${u}"
  fn="$OUT/js/js_${i}.js"
  if [ -n "$TO" ]; then
    $TO 10s curl -sS "$u" -o "$fn" || warn "download js fail: $u"
  else
    curl -sS "$u" -o "$fn" || warn "download js fail: $u"
  fi
done < "$js_list"

# 3) discover APIs from JS
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
ok "api_found=$(wc -l < "$api_list" | tr -d ' ')"

# always include runs_v3
echo "/api/vsp/runs_v3?limit=5&include_ci=1" >> "$api_list"

# 4) fetch RID (robust: save hdr/body)
RID=""
runs_hdr="$OUT/api/runs_v3.hdr"
runs_body="$OUT/api/runs_v3.body"
if [ -n "$TO" ]; then
  $TO 8s curl -sS -D "$runs_hdr" "$BASE/api/vsp/runs_v3?limit=5&include_ci=1" -o "$runs_body" || true
else
  curl -sS -D "$runs_hdr" "$BASE/api/vsp/runs_v3?limit=5&include_ci=1" -o "$runs_body" || true
fi

# try parse rid only if looks like JSON
head2="$(head -c 2 "$runs_body" 2>/dev/null || true)"
if [[ "$head2" == "{"* || "$head2" == "["* ]]; then
  RID="$(python3 - <<'PY' "$runs_body" 2>/dev/null || true
import sys,json
p=sys.argv[1]
j=json.load(open(p,'r',encoding='utf-8',errors='replace'))
rid=""
if isinstance(j,dict) and j.get("rid"): rid=j["rid"]
if not rid and isinstance(j,dict):
  for k in ("items","runs"):
    arr=j.get(k) or []
    if isinstance(arr,list) and arr and isinstance(arr[0],dict) and arr[0].get("rid"):
      rid=arr[0]["rid"]; break
print(rid)
PY
)"
else
  warn "runs_v3 not json (head='$head2'). see $runs_hdr and $runs_body"
fi
log "RID=${RID:-<empty>}"

echo "path,http,time_total,is_json,keys_or_len" > "$OUT/apis_probe.csv"

need_rid_re='/(datasource_v3|data_source_v1|findings_unified_v1|exports_v1|overrides_v1|run_status_v1|dashboard_kpis_v4)$'

normalize_path(){
  local path="$1"
  # rewrite old runs -> runs_v3
  if [[ "$path" == /api/vsp/runs\?* ]] || [[ "$path" == /api/vsp/runs$* ]]; then
    path="${path/\/api\/vsp\/runs/\/api\/vsp\/runs_v3}"
  fi
  # fill rid= empty
  if [ -n "$RID" ] && [[ "$path" == *"rid="* ]]; then
    path="$(echo "$path" | sed -E "s/rid=(&|$)/rid=${RID}\1/g")"
  fi
  # append rid if needed
  if [ -n "$RID" ] && echo "$path" | grep -Eq "$need_rid_re" && ! echo "$path" | grep -q "rid="; then
    if [[ "$path" == *"?"* ]]; then path="${path}&rid=${RID}"; else path="${path}?rid=${RID}"; fi
  fi
  echo "$path"
}

probe_one(){
  local raw="$1"
  local path; path="$(normalize_path "$raw")"
  local url="$BASE$path"
  local tmp="$OUT/api/$(echo "$path" | tr '/?&=' '____').resp"
  local hdr="$OUT/api/$(echo "$path" | tr '/?&=' '____').hdr"

  local time_total=""
  if [ -n "$TO" ]; then
    time_total="$($TO 10s curl -sS -D "$hdr" -o "$tmp" -w "time_total=%{time_total}\n" "$url" 2>/dev/null | tail -n1 | awk -F= '{print $2}' || true)"
  else
    time_total="$(curl -sS -D "$hdr" -o "$tmp" -w "time_total=%{time_total}\n" "$url" 2>/dev/null | tail -n1 | awk -F= '{print $2}' || true)"
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

# probe up to 25
n=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  n=$((n+1))
  probe_one "$path" || true
  [ "$n" -ge 25 ] && break
done < "$api_list"

ok "done: $OUT"
echo "[DONE] OUT=$OUT"
