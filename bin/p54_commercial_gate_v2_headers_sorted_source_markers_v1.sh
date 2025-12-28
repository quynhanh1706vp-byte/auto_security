#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p54_gate_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need awk; need grep; need sort; need uniq; need head; need ls; need python3; need mkdir; need cp; need sha256sum

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release in $RELROOT"; exit 2; }
ATT="$latest_release/evidence/p54_gate_${TS}"
mkdir -p "$ATT"
echo "[OK] latest_release=$latest_release"

tabs=(
  "/vsp5|Dashboard"
  "/runs|Runs & Reports"
  "/data_source|Data Source"
  "/settings|Settings"
  "/rule_overrides|Rule Overrides"
)

ok=1
: > "$EVID/reasons.txt"
: > "$EVID/warnings.txt"
: > "$EVID/tab_status.tsv"

slugify(){ echo "$1" | tr ' /&' '___' | tr -cd 'A-Za-z0-9_-' ; }

echo "name	path	code" > "$EVID/tab_status.tsv"
for item in "${tabs[@]}"; do
  path="${item%%|*}"
  name="${item##*|}"
  slug="$(slugify "$name")"
  hdr="$EVID/${slug}_hdr.txt"
  html="$EVID/${slug}.html"

  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 12 "$BASE$path" || true)"
  echo -e "$name\t$path\t$code" >> "$EVID/tab_status.tsv"

  curl -sS -D "$hdr" -o "$html" --connect-timeout 2 --max-time 15 --range 0-260000 "$BASE$path" || true
  if [ "$code" != "200" ]; then ok=0; echo "tab_${slug}_http_${code}" >> "$EVID/reasons.txt"; fi
done

# Header fingerprint (order-independent): normalize + sort lines before hashing
for f in "$EVID"/*_hdr.txt; do
  bn="$(basename "$f" .txt)"
  awk 'BEGIN{IGNORECASE=1}
       /^HTTP\/|^Cache-Control:|^Pragma:|^Expires:|^X-Content-Type-Options:|^Referrer-Policy:|^X-Frame-Options:/{
         gsub("\r",""); print
       }' "$f" | sort -f > "$EVID/${bn}_hdr_norm_sorted.txt"
done

python3 - <<'PY'
from pathlib import Path
import hashlib

d=Path(".")
E=Path("out_ci")
gate=sorted([p for p in E.glob("p54_gate_*") if p.is_dir()], reverse=True)[0]

groups={}
rows=[]
for f in sorted(gate.glob("*_hdr_norm_sorted.txt")):
    h=hashlib.sha256(f.read_bytes()).hexdigest()[:16]
    groups.setdefault(h, []).append(f.name)
    rows.append((f.name, h))

(gate/"header_fingerprints.tsv").write_text("\n".join([f"{a}\t{b}" for a,b in rows])+"\n")
(gate/"header_fp_count.txt").write_text(str(len(groups))+"\n")

# Write group details for audit
out=[]
out.append(f"fp_count={len(groups)}")
for h,names in sorted(groups.items(), key=lambda x: (-len(x[1]), x[0])):
    out.append(f"\n== FP {h} ({len(names)} files) ==")
    for n in names: out.append(f"- {n}")
    out.append("---- sorted headers ----")
    out.append((gate/names[0]).read_text(errors="replace"))
(gate/"header_fingerprint_groups.txt").write_text("\n".join(out), encoding="utf-8")
print("[OK] fp_count=", len(groups))
PY

fp="$(cat "$EVID/header_fp_count.txt" 2>/dev/null || echo 99)"
if [ "$fp" -gt 1 ]; then
  echo "headers_fingerprint_mismatch" >> "$EVID/warnings.txt"
fi

# Source-only marker scan (commercial-correct)
: > "$EVID/source_marker_hits.txt"
for kw in DEBUG TODO TRACE "not available" "N/A"; do
  echo "===== KW: $kw =====" >> "$EVID/source_marker_hits.txt"
  grep -RIn --line-number --exclude='*.bak_*' --exclude='*.disabled_*' \
    -e "$kw" templates static/js 2>/dev/null | head -n 120 >> "$EVID/source_marker_hits.txt" || true
done

# If there are real hits (excluding section headers)
if grep -qE '^[0-9]+:' "$EVID/source_marker_hits.txt"; then
  echo "source_markers_found" >> "$EVID/warnings.txt"
fi

VER="$OUT/p54_gate_v2_verdict_${TS}.json"
python3 - <<PY
import json, time
from pathlib import Path
reasons=[l.strip() for l in Path("$EVID/reasons.txt").read_text(errors="replace").splitlines() if l.strip()]
warns=[l.strip() for l in Path("$EVID/warnings.txt").read_text(errors="replace").splitlines() if l.strip()]
j={"ok": (len(reasons)==0),
   "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
   "p54_gate_v2": {"base":"$BASE","latest_release":"$latest_release",
                   "evidence_dir":"$EVID","attached_dir":"$ATT",
                   "reasons": reasons, "warnings": warns,
                   "header_fp_count": int(open("$EVID/header_fp_count.txt").read().strip() or "99")}}
print(json.dumps(j, indent=2))
Path("$VER").write_text(json.dumps(j, indent=2))
PY

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
cp -f "$VER" "$ATT/" 2>/dev/null || true

python3 - <<PY
import json,sys
j=json.load(open("$VER"))
sys.exit(0 if j.get("ok") else 2)
PY

echo "[DONE] P54 PASS (gate v2 attached)"
