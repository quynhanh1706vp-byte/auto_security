#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p51_1_gate_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need awk; need sed; need grep; need head; need tail; need sort; need uniq; need wc; need ls; need python3; need cp; need mkdir
log(){ echo "[$(date +%H:%M:%S)] $*"; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release in $RELROOT"; exit 2; }
ATT="$latest_release/evidence/p51_1_gate_${TS}"
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
reasons_file="$EVID/reasons.txt"
warns_file="$EVID/warnings.txt"
: > "$reasons_file"
: > "$warns_file"

slugify(){ echo "$1" | tr ' /&' '___' | tr -cd 'A-Za-z0-9_-' ; }

log "== [P51.1/1] fetch tabs (html+headers) =="
: > "$EVID/tab_status.txt"
for item in "${tabs[@]}"; do
  path="${item%%|*}"
  name="${item##*|}"
  slug="$(slugify "$name")"
  hdr="$EVID/${slug}_hdr.txt"
  html="$EVID/${slug}.html"
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 8 "$BASE$path" || true)"
  echo "$name|$path|$code|$slug" >> "$EVID/tab_status.txt"
  curl -sS -D "$hdr" -o "$html" --connect-timeout 2 --max-time 12 --range 0-220000 "$BASE$path" || true
  if [ "$code" != "200" ]; then
    PASS=0
    echo "tab_${slug}_http_${code}" >> "$reasons_file"
  fi
done

log "== [P51.1/2] header consistency fingerprints =="
for f in "$EVID"/*_hdr.txt; do
  bn="$(basename "$f" .txt)"
  awk 'BEGIN{IGNORECASE=1}
       /^HTTP\/|^Content-Type:|^Cache-Control:|^Pragma:|^Expires:|^X-Content-Type-Options:|^Content-Security-Policy:|^Referrer-Policy:|^X-Frame-Options:/{
         gsub("\r",""); print
       }' "$f" > "$EVID/${bn}_hdr_norm.txt"
done

python3 - <<'PY'
from pathlib import Path
import hashlib
d=Path("out_ci")
dirs=sorted([p for p in d.glob("p51_1_gate_*") if p.is_dir()], reverse=True)
p=dirs[0]
rows=[]
fps=set()
for f in sorted(p.glob("*_hdr_norm.txt")):
    data=f.read_bytes()
    h=hashlib.sha256(data).hexdigest()[:16]
    rows.append((f.name,h))
    fps.add(h)
(p/"header_fingerprints.txt").write_text("\n".join([f"{a}\t{b}" for a,b in rows])+"\n")
(p/"header_fp_count.txt").write_text(str(len(fps))+"\n")
print("[OK] fp_count=", len(fps))
PY

fp_count="$(cat "$EVID/header_fp_count.txt" 2>/dev/null || echo 99)"
if [ "$fp_count" -gt 1 ]; then
  echo "headers_fingerprint_mismatch" >> "$warns_file"
fi

log "== [P51.1/3] extract static urls + sample head checks =="
: > "$EVID/static_urls.txt"
for h in "$EVID"/*.html; do
  grep -Eo 'src="/static/[^"]+|href="/static/[^"]+' "$h" \
    | sed 's/^(src|href)=//' | sed 's/^src="//;s/^href="//' \
    | sed 's/"$//' >> "$EVID/static_urls.txt" || true
done
sort -u "$EVID/static_urls.txt" > "$EVID/static_urls_uniq.txt" || true

python3 - <<'PY'
import subprocess
from pathlib import Path
p=Path("out_ci")
dirs=sorted([d for d in p.glob("p51_1_gate_*") if d.is_dir()], reverse=True)
d=dirs[0]
urls=[u.strip() for u in (d/"static_urls_uniq.txt").read_text(errors="replace").splitlines() if u.strip()]
sample=urls[:80]
out=[]
def head(u):
    cmd=['curl','-sS','-D-','-o','/dev/null','--connect-timeout','2','--max-time','6',f'http://127.0.0.1:8910{u}']
    r=subprocess.run(cmd, capture_output=True, text=True)
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
    return code, ctype
for u in sample:
    c,t=head(u)
    out.append((u,c,t))
(d/"static_head_sample.tsv").write_text("\n".join([f"{u}\t{c}\t{t}" for u,c,t in out])+"\n")
bad=sum(1 for _,c,_ in out if c!="200")
(d/"static_sample_summary.txt").write_text(f"bad_static_sample={bad}\n")
print("[OK] static_sample rows", len(out), "bad", bad)
PY

bad_static="$(awk -F= '{print $2}' "$EVID/static_sample_summary.txt" 2>/dev/null || echo 0)"
if [ "${bad_static:-0}" -gt 0 ]; then
  PASS=0
  echo "static_sample_non200_${bad_static}" >> "$reasons_file"
fi

log "== [P51.1/4] scan markers (post-P52 should be empty) =="
markers='DEBUG|TODO|TRACE|not available|N/A|undefined|null'
hitfile="$EVID/html_marker_hits.txt"
: > "$hitfile"
for h in "$EVID"/*.html; do
  if grep -Ein "$markers" "$h" | head -n 40 >> "$hitfile"; then
    echo "---- $(basename "$h") ----" >> "$hitfile"
  fi
done
if [ -s "$hitfile" ]; then
  echo "html_markers_found" >> "$warns_file"
fi

log "== [P51.1/5] attach evidence + verdict json =="
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true

# Build JSON lists safely from files
python3 - <<PY
import json, time
from pathlib import Path
reasons=[l.strip() for l in Path("$reasons_file").read_text(errors="replace").splitlines() if l.strip()]
warns=[l.strip() for l in Path("$warns_file").read_text(errors="replace").splitlines() if l.strip()]
ok = (len(reasons)==0)
j={"ok": ok, "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
   "p51_1": {"base":"$BASE","latest_release":"$latest_release",
             "evidence_dir":"$EVID","attached_dir":"$ATT",
             "reasons": reasons, "warnings": warns}}
print(json.dumps(j, indent=2))
Path("$OUT/p51_1_verdict_${TS}.json").write_text(json.dumps(j, indent=2))
PY

VER="$OUT/p51_1_verdict_${TS}.json"
cp -f "$VER" "$ATT/" 2>/dev/null || true

if python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); sys.exit(0 if j.get("ok") else 2)' "$VER"; then
  log "[PASS] wrote $VER"
  log "[DONE] P51.1 PASS"
else
  log "[FAIL] wrote $VER"
  log "[DONE] P51.1 FAIL"
  exit 2
fi
