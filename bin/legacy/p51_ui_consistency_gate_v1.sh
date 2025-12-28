#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p51_gate_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need awk; need sed; need grep; need head; need tail; need sort; need uniq; need wc; need ls; need python3
log(){ echo "[$(date +%H:%M:%S)] $*"; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release in $RELROOT"; exit 2; }
ATT="$latest_release/evidence/p51_gate_${TS}"
mkdir -p "$ATT"
log "[OK] latest_release=$latest_release"

tabs=(
  "/vsp5|Dashboard"
  "/runs|Runs & Reports"
  "/data_source|Data Source"
  "/settings|Settings"
  "/rule_overrides|Rule Overrides"
)

PASS=1
REASONS=()

fetch_tab(){
  local path="$1" name="$2" slug="$3"
  local hdr="$EVID/${slug}_hdr.txt"
  local html="$EVID/${slug}.html"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 6 "$BASE$path" || true)"
  echo "$name|$path|$code|$slug" >> "$EVID/tab_status.txt"
  curl -sS -D "$hdr" -o "$html" --connect-timeout 2 --max-time 10 --range 0-200000 "$BASE$path" || true
  if [ "$code" != "200" ]; then PASS=0; REASONS+=("tab_${slug}_http_${code}"); fi
}

log "== [P51/1] fetch tabs =="
: > "$EVID/tab_status.txt"
for item in "${tabs[@]}"; do
  path="${item%%|*}"
  name="${item##*|}"
  slug="$(echo "$name" | tr ' /&' '___' | tr -cd 'A-Za-z0-9_-' )"
  fetch_tab "$path" "$name" "$slug"
done

log "== [P51/2] header consistency (core cache+ctype) =="
# Normalize headers: only keep relevant lines
for f in "$EVID"/*_hdr.txt; do
  bn="$(basename "$f" .txt)"
  awk 'BEGIN{IGNORECASE=1}
       /^HTTP\/|^Content-Type:|^Cache-Control:|^Pragma:|^Expires:|^X-Content-Type-Options:|^Content-Security-Policy:|^Referrer-Policy:|^X-Frame-Options:/ {
         gsub("\r",""); print
       }' "$f" > "$EVID/${bn}_hdr_norm.txt"
done

# Compare normalized sets
cat "$EVID"/*_hdr_norm.txt > "$EVID/headers_all_norm.txt" 2>/dev/null || true
# Make a per-tab fingerprint
python3 - <<'PY'
from pathlib import Path
import hashlib
root=Path("out_ci")
# find latest p51 dir
dirs=sorted([p for p in root.glob("p51_gate_*") if p.is_dir()], key=lambda p:p.name, reverse=True)
p51=dirs[0]
rows=[]
for f in sorted(p51.glob("*_hdr_norm.txt")):
    data=f.read_bytes()
    h=hashlib.sha256(data).hexdigest()[:16]
    rows.append((f.name, h))
out=p51/"header_fingerprints.txt"
out.write_text("\n".join([f"{a}\t{b}" for a,b in rows])+"\n")
print("[OK] wrote", out)
PY

# If fingerprints differ, WARN (not necessarily fail), but record
if [ "$(cut -f2 "$EVID/header_fingerprints.txt" | sort -u | wc -l | awk '{print $1}')" -gt 1 ]; then
  echo "[WARN] header fingerprints differ across tabs" | tee "$EVID/header_warn.txt" >/dev/null
else
  echo "[OK] headers consistent (fingerprints match)" | tee "$EVID/header_ok.txt" >/dev/null
fi

log "== [P51/3] extract JS/CSS urls from HTML + check duplicates =="
# Extract static urls
: > "$EVID/static_urls.txt"
for h in "$EVID"/*.html; do
  grep -Eo 'src="/static/[^"]+|href="/static/[^"]+' "$h" \
    | sed 's/^(src|href)=//' | sed 's/^src="//;s/^href="//' \
    | sed 's/"$//' >> "$EVID/static_urls.txt" || true
done
sort -u "$EVID/static_urls.txt" > "$EVID/static_urls_uniq.txt" || true

# Basename duplication
awk -F/ '{print $NF}' "$EVID/static_urls_uniq.txt" | sed 's/[?].*$//' \
  | sort | uniq -c | sort -nr > "$EVID/static_basename_dupe.txt" || true

# Flag suspicious: same basename appearing 2+ times with different query/paths
if awk '$1>=2{exit 0} END{exit 1}' "$EVID/static_basename_dupe.txt"; then
  echo "[WARN] duplicate static basenames exist (review)" | tee "$EVID/static_dupe_warn.txt" >/dev/null
fi

log "== [P51/4] verify static assets 200 + content-type sanity (sample up to 80) =="
python3 - <<'PY'
import subprocess, shlex
from pathlib import Path
p = Path("out_ci")
dirs=sorted([d for d in p.glob("p51_gate_*") if d.is_dir()], reverse=True)
d=dirs[0]
urls=[u.strip() for u in (d/"static_urls_uniq.txt").read_text().splitlines() if u.strip()]
sample=urls[:80]
out=[]
def head(url):
    cmd=f'curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 6 "http://127.0.0.1:8910{url}"'
    r=subprocess.run(cmd, shell=True, capture_output=True, text=True)
    hdr=r.stdout.replace("\r","")
    code="000"
    for line in hdr.splitlines():
        if line.startswith("HTTP/"):
            code=line.split()[1]
            break
    ctype=""
    for line in hdr.splitlines():
        if line.lower().startswith("content-type:"):
            ctype=line.split(":",1)[1].strip()
            break
    return code, ctype, hdr
for u in sample:
    code, ctype, hdr = head(u)
    out.append((u, code, ctype))
(d/"static_head_sample.tsv").write_text("\n".join([f"{u}\t{c}\t{t}" for u,c,t in out])+"\n")
print("[OK] wrote static_head_sample.tsv rows=", len(out))
PY

# Soft fail if any static in sample not 200
bad_static="$(awk -F'\t' '$2!="200"{c++} END{print c+0}' "$EVID/static_head_sample.tsv" 2>/dev/null || echo 0)"
echo "bad_static_sample=$bad_static" | tee "$EVID/static_sample_summary.txt" >/dev/null
if [ "$bad_static" -gt 0 ]; then
  PASS=0
  REASONS+=("static_sample_non200_${bad_static}")
fi

log "== [P51/5] scan HTML for debug markers (soft fail if found) =="
markers='DEBUG|TODO|TRACE|not available|N/A|undefined|null'
hitfile="$EVID/html_marker_hits.txt"
: > "$hitfile"
for h in "$EVID"/*.html; do
  bn="$(basename "$h")"
  if grep -Ein "$markers" "$h" | head -n 30 >> "$hitfile"; then
    echo "---- in $bn ----" >> "$hitfile"
  fi
done
if [ -s "$hitfile" ]; then
  echo "[WARN] markers found (review $hitfile)" | tee "$EVID/markers_warn.txt" >/dev/null
  # For commercial: mark as WARN only; uncomment to hard fail:
  # PASS=0; REASONS+=("html_markers_found")
fi

log "== [P51/6] attach evidence + verdict =="
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true

VER="$OUT/p51_verdict_${TS}.json"
python3 - <<PY
import json, time
ok = bool(int("$PASS"))
reasons = ${REASONS[@]+"["$(printf '"%s",' "${REASONS[@]}" | sed 's/,$//')"]"}
if reasons == "" or reasons is None:
    reasons = []
j={"ok": ok, "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
   "p51": {"base":"$BASE","latest_release":"$latest_release","evidence_dir":"$EVID","attached_dir":"$ATT","reasons": reasons}}
print(json.dumps(j, indent=2))
open("$VER","w").write(json.dumps(j, indent=2))
PY
cp -f "$VER" "$ATT/" 2>/dev/null || true

if [ "$PASS" -eq 1 ]; then
  log "[PASS] wrote $VER"
  log "[DONE] P51 PASS"
else
  log "[FAIL] wrote $VER"
  log "[DONE] P51 FAIL"
  exit 2
fi
