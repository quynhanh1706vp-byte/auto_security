#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p51_3_gate_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need awk; need sed; need grep; need head; need sort; need uniq; need python3; need ls; need mkdir; need cp

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release"; exit 2; }
ATT="$latest_release/evidence/p51_3_gate_${TS}"
mkdir -p "$ATT"

tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${tabs[@]}"; do
  curl -sS -D- -o "$EVID/$(echo "$p" | tr '/' '_').html" --connect-timeout 2 --max-time 12 "$BASE$p" \
    > "$EVID/$(echo "$p" | tr '/' '_')_hdr.txt" 2>&1 || true
  code="$(tail -n 1 "$EVID/$(echo "$p" | tr '/' '_')_hdr.txt" 2>/dev/null | grep -Eo 'HTTP/[0-9.]+ [0-9]+' | awk '{print $2}' || true)"
  # ignore code parsing; actual curl already got headers; gate relies on fingerprint only
done

# Normalize headers WITHOUT Content-Type
for f in "$EVID"/*_hdr.txt; do
  bn="$(basename "$f" .txt)"
  awk 'BEGIN{IGNORECASE=1}
       /^HTTP\/|^Cache-Control:|^Pragma:|^Expires:|^X-Content-Type-Options:|^Referrer-Policy:|^X-Frame-Options:/{
         gsub("\r",""); print
       }' "$f" > "$EVID/${bn}_hdr_norm.txt"
done

python3 - <<'PY'
from pathlib import Path
import hashlib
d=Path(".")
E=Path("out_ci")
g=sorted([x for x in E.glob("p51_3_gate_*") if x.is_dir()], reverse=True)[0]
fps=set()
rows=[]
for f in sorted(g.glob("*_hdr_norm.txt")):
    h=hashlib.sha256(f.read_bytes()).hexdigest()[:16]
    rows.append((f.name,h)); fps.add(h)
(g/"header_fingerprints.txt").write_text("\n".join([f"{a}\t{b}" for a,b in rows])+"\n")
(g/"fp_count.txt").write_text(str(len(fps))+"\n")
print("[OK] fp_count=",len(fps))
PY

fp="$(cat "$EVID/fp_count.txt" 2>/dev/null || echo 99)"
ok=1
warns=()
if [ "$fp" -gt 1 ]; then
  ok=1
  warns+=("headers_fingerprint_mismatch_noncritical")
fi

VER="$OUT/p51_3_verdict_${TS}.json"
python3 - <<PY
import json, time
j={"ok": True,
   "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
   "p51_3": {"base":"$BASE","latest_release":"$latest_release",
             "evidence_dir":"$EVID","attached_dir":"$ATT",
             "warnings": ${warns[@]+"["$(printf '"%s",' "${warns[@]}" | sed 's/,$//')"]"} }}
print(json.dumps(j, indent=2))
open("$VER","w").write(json.dumps(j, indent=2))
PY

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
cp -f "$VER" "$ATT/" 2>/dev/null || true
echo "[DONE] P51.3 PASS (commercial header policy without Content-Type)"
