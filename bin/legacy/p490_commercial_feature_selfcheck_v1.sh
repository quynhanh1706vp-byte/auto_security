#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p490_feature_${TS}"
mkdir -p "$OUT/js" "$OUT/html" "$OUT/api" "$OUT/logs"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/logs/run.log"; exit 2; }; }
need curl; need python3; need awk; need sed; need grep; need date
TO="$(command -v timeout || true)"

ok(){ echo "[OK] $*" | tee -a "$OUT/logs/run.log"; }
warn(){ echo "[WARN] $*" | tee -a "$OUT/logs/run.log"; }
fail(){ echo "[FAIL] $*" | tee -a "$OUT/logs/run.log"; }

tabs=(/c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)

echo "== [P490] BASE=$BASE TS=$TS ==" | tee "$OUT/SUMMARY.txt"

# 1) Fetch HTML + headers, check release header consistency
rel_ts=""
rel_sha=""
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
  rpkg="$(awk 'BEGIN{IGNORECASE=1} /^X-VSP-RELEASE-PKG:/{sub("\r",""); $1=""; sub(/^ /,""); print}' "$fhdr" || true)"

  echo "" | tee -a "$OUT/SUMMARY.txt" >/dev/null
  echo "== TAB $p ==" | tee -a "$OUT/SUMMARY.txt"
  echo "http=$code" | tee -a "$OUT/SUMMARY.txt"
  echo "$ct" | tee -a "$OUT/SUMMARY.txt"
  echo "Content-Length=${len:-?}" | tee -a "$OUT/SUMMARY.txt"
  echo "X-VSP-RELEASE-TS=${rts:-?}" | tee -a "$OUT/SUMMARY.txt"
  echo "X-VSP-RELEASE-SHA=${rsha:-?}" | tee -a "$OUT/SUMMARY.txt"
  echo "X-VSP-RELEASE-PKG=${rpkg:-?}" | tee -a "$OUT/SUMMARY.txt"

  # Basic sanity
  if [ "${code:-}" != "200" ]; then fail "$p HTTP=$code"; fi
  if [ -n "${len:-}" ] && [ "$len" -lt 2500 ]; then warn "$p small HTML len=$len"; fi

  # Release consistency
  if [ -z "$rel_ts" ] && [ -n "$rts" ]; then rel_ts="$rts"; fi
  if [ -z "$rel_sha" ] && [ -n "$rsha" ]; then rel_sha="$rsha"; fi
  if [ -n "$rel_ts" ] && [ -n "$rts" ] && [ "$rel_ts" != "$rts" ]; then warn "release TS mismatch on $p ($rel_ts vs $rts)"; fi
  if [ -n "$rel_sha" ] && [ -n "$rsha" ] && [ "$rel_sha" != "$rsha" ]; then warn "release SHA mismatch on $p ($rel_sha vs $rsha)"; fi
done

echo "" | tee -a "$OUT/SUMMARY.txt" >/dev/null
echo "== RELEASE CONSISTENCY ==" | tee -a "$OUT/SUMMARY.txt"
echo "TS=$rel_ts" | tee -a "$OUT/SUMMARY.txt"
echo "SHA=$rel_sha" | tee -a "$OUT/SUMMARY.txt"

# 2) Extract JS URLs from HTML and download for evidence
js_list="$OUT/js_urls.txt"
: > "$js_list"
for p in "${tabs[@]}"; do
  fhtml="$OUT/html/$(echo "$p" | tr '/?' '__').html"
  # naive extraction: src="...js"
  grep -Eo 'src="[^"]+\.js[^"]*"' "$fhtml" \
    | sed -E 's/^src="//; s/"$//' \
    >> "$js_list" || true
done
# normalize + dedupe
sed -i 's/&amp;/\&/g' "$js_list" 2>/dev/null || true
python3 - <<'PY' "$js_list" > "$OUT/js_urls_dedup.txt"
import sys
p=sys.argv[1]
seen=[]
for line in open(p,encoding="utf-8",errors="replace"):
    u=line.strip()
    if not u: 
        continue
    if u not in seen:
        seen.append(u)
for u in seen:
    print(u)
PY
mv -f "$OUT/js_urls_dedup.txt" "$js_list"

js_count="$(wc -l < "$js_list" | tr -d ' ')"
echo "" | tee -a "$OUT/SUMMARY.txt" >/dev/null
echo "== JS URLS ==" | tee -a "$OUT/SUMMARY.txt"
echo "count=$js_count (download to $OUT/js)" | tee -a "$OUT/SUMMARY.txt"

i=0
while IFS= read -r u; do
  i=$((i+1))
  # absolutize
  if [[ "$u" != http* ]]; then
    u="$BASE${u}"
  fi
  fn="$OUT/js/js_${i}.js"
  if [ -n "$TO" ]; then
    $TO 10s curl -sS "$u" -o "$fn" || { warn "download js fail: $u"; continue; }
  else
    curl -sS "$u" -o "$fn" || { warn "download js fail: $u"; continue; }
  fi
done < "$js_list"

# 3) Discover /api/... endpoints from JS and probe
api_list="$OUT/apis_found.txt"
: > "$api_list"
grep -RhoE '(["'\'']\/api\/[^"'\'' ]+)' "$OUT/js" 2>/dev/null \
  | sed -E 's/^["'\'']//; s/["'\'']$//' \
  | sed -E 's/[);,]+$//' \
  | grep -E '^/api/' \
  >> "$api_list" || true

python3 - <<'PY' "$api_list" > "$OUT/apis_found_dedup.txt"
import sys
p=sys.argv[1]
seen=[]
for line in open(p,encoding="utf-8",errors="replace"):
    u=line.strip()
    if not u: 
        continue
    # remove trailing quotes/brackets fragments
    for ch in ['"',"'","\\"]:
        u=u.replace(ch,'')
    if u not in seen:
        seen.append(u)
for u in seen:
    print(u)
PY
mv -f "$OUT/apis_found_dedup.txt" "$api_list"

api_count="$(wc -l < "$api_list" | tr -d ' ')"
echo "" | tee -a "$OUT/SUMMARY.txt" >/dev/null
echo "== API DISCOVERY ==" | tee -a "$OUT/SUMMARY.txt"
echo "found=$api_count (from JS grep)" | tee -a "$OUT/SUMMARY.txt"

# Always probe the known runs endpoint (contract)
echo "/api/vsp/runs_v3?limit=5&include_ci=1" >> "$api_list"

# de-dupe again
python3 - <<'PY' "$api_list" > "$OUT/apis_probe_list.txt"
import sys
p=sys.argv[1]
seen=[]
for line in open(p,encoding="utf-8",errors="replace"):
    u=line.strip()
    if not u: continue
    if u not in seen:
        seen.append(u)
for u in seen:
    print(u)
PY
mv -f "$OUT/apis_probe_list.txt" "$api_list"

echo "path,http,time_total,is_json,keys_or_len" > "$OUT/apis_probe.csv"

probe_one(){
  local path="$1"
  local url="$BASE$path"
  local tmp="$OUT/api/$(echo "$path" | tr '/?&=' '____').resp"
  local hdr="$OUT/api/$(echo "$path" | tr '/?&=' '____').hdr"
  local outmeta="$OUT/api/$(echo "$path" | tr '/?&=' '____').meta"

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
  echo "code=$code time_total=${time_total:-} ct=${ct:-}" > "$outmeta"
}

# Probe up to 25 endpoints to keep it fast
n=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  n=$((n+1))
  probe_one "$path" || true
  [ "$n" -ge 25 ] && break
done < "$api_list"

# 4) Hard contract check for runs_v3 keys
echo "" >> "$OUT/SUMMARY.txt"
echo "== CONTRACT CHECK: runs_v3 ==" >> "$OUT/SUMMARY.txt"
python3 - <<'PY' "$BASE" >> "$OUT/SUMMARY.txt"
import sys, json, urllib.request
base=sys.argv[1].rstrip("/")
url=base+"/api/vsp/runs_v3?limit=5&include_ci=1"
try:
    with urllib.request.urlopen(url, timeout=6) as r:
        data=r.read().decode("utf-8","replace")
    j=json.loads(data)
    keys=sorted(j.keys()) if isinstance(j, dict) else []
    ok = isinstance(j, dict) and all(k in j for k in ["ok","items","runs","total"]) and isinstance(j.get("items"), list) and isinstance(j.get("runs"), list)
    print("ok=", ok, "keys=", keys)
    print("total=", j.get("total"))
except Exception as e:
    print("FAIL runs_v3:", repr(e))
PY

ok "done: $OUT"
echo "[DONE] OUT=$OUT"
