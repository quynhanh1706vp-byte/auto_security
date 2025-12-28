#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p51_2_gate_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need awk; need sed; need grep; need head; need sort; need uniq; need wc; need ls; need python3; need cp; need mkdir
log(){ echo "[$(date +%H:%M:%S)] $*"; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release in $RELROOT"; exit 2; }
ATT="$latest_release/evidence/p51_2_gate_${TS}"
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
: > "$EVID/reasons.txt"
: > "$EVID/warnings.txt"
: > "$EVID/tab_status.txt"

slugify(){ echo "$1" | tr ' /&' '___' | tr -cd 'A-Za-z0-9_-' ; }

log "== [P51.2/1] fetch tabs =="
for item in "${tabs[@]}"; do
  path="${item%%|*}"
  name="${item##*|}"
  slug="$(slugify "$name")"
  hdr="$EVID/${slug}_hdr.txt"
  html="$EVID/${slug}.html"
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 10 "$BASE$path" || true)"
  echo "$name|$path|$code|$slug" >> "$EVID/tab_status.txt"
  curl -sS -D "$hdr" -o "$html" --connect-timeout 2 --max-time 12 --range 0-220000 "$BASE$path" || true
  if [ "$code" != "200" ]; then PASS=0; echo "tab_${slug}_http_${code}" >> "$EVID/reasons.txt"; fi
done

log "== [P51.2/2] header fingerprint (exclude CSP to avoid noise) =="
for f in "$EVID"/*_hdr.txt; do
  bn="$(basename "$f" .txt)"
  awk 'BEGIN{IGNORECASE=1}
       /^HTTP\/|^Content-Type:|^Cache-Control:|^Pragma:|^Expires:|^X-Content-Type-Options:|^Referrer-Policy:|^X-Frame-Options:/{
         gsub("\r",""); print
       }' "$f" > "$EVID/${bn}_hdr_norm.txt"
done

python3 - <<'PY'
from pathlib import Path
import hashlib
p=Path("out_ci")
dirs=sorted([d for d in p.glob("p51_2_gate_*") if d.is_dir()], reverse=True)
d=dirs[0]
fps=set()
rows=[]
for f in sorted(d.glob("*_hdr_norm.txt")):
    h=hashlib.sha256(f.read_bytes()).hexdigest()[:16]
    rows.append((f.name,h)); fps.add(h)
(d/"header_fingerprints.txt").write_text("\n".join([f"{a}\t{b}" for a,b in rows])+"\n")
(d/"header_fp_count.txt").write_text(str(len(fps))+"\n")
print("[OK] fp_count=",len(fps))
PY

fp_count="$(cat "$EVID/header_fp_count.txt" 2>/dev/null || echo 99)"
if [ "$fp_count" -gt 1 ]; then
  echo "headers_fingerprint_mismatch" >> "$EVID/warnings.txt"
fi

log "== [P51.2/3] marker scan (remove null/undefined false-positive) =="
markers='DEBUG|TODO|TRACE|not available|N/A'
hitfile="$EVID/html_marker_hits.txt"
: > "$hitfile"
for h in "$EVID"/*.html; do
  if grep -Ein "$markers" "$h" | head -n 40 >> "$hitfile"; then
    echo "---- $(basename "$h") ----" >> "$hitfile"
  fi
done
if [ -s "$hitfile" ]; then
  echo "html_markers_found" >> "$EVID/warnings.txt"
fi

log "== [P51.2/4] verdict + attach =="
python3 - <<PY
import json, time
from pathlib import Path
reasons=[l.strip() for l in Path("$EVID/reasons.txt").read_text(errors="replace").splitlines() if l.strip()]
warns=[l.strip() for l in Path("$EVID/warnings.txt").read_text(errors="replace").splitlines() if l.strip()]
ok=(len(reasons)==0)
j={"ok": ok, "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
   "p51_2": {"base":"$BASE","latest_release":"$latest_release",
             "evidence_dir":"$EVID","attached_dir":"$ATT",
             "reasons": reasons, "warnings": warns}}
print(json.dumps(j, indent=2))
Path("$OUT/p51_2_verdict_${TS}.json").write_text(json.dumps(j, indent=2))
PY

VER="$OUT/p51_2_verdict_${TS}.json"
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
cp -f "$VER" "$ATT/" 2>/dev/null || true

if python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); sys.exit(0 if j.get("ok") else 2)' "$VER"; then
  log "[PASS] wrote $VER"
  log "[DONE] P51.2 PASS"
else
  log "[FAIL] wrote $VER"
  log "[DONE] P51.2 FAIL"
  exit 2
fi
