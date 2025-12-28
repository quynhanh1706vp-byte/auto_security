#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p51_2b_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ls; need head; need awk; need sed; need grep; need python3; need sort; need uniq

latest_gate="$(ls -1dt "$OUT"/p51_2_gate_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_gate:-}" ] && [ -d "$latest_gate" ] || { echo "[ERR] no p51_2_gate_* found"; exit 2; }
echo "[OK] latest_gate=$latest_gate"

# Header diff: group by fingerprint
python3 - <<PY
from pathlib import Path
import hashlib, re
g=Path("$latest_gate")
files=sorted(g.glob("*_hdr_norm.txt"))
groups={}
for f in files:
    h=hashlib.sha256(f.read_bytes()).hexdigest()[:16]
    groups.setdefault(h, []).append(f.name)

out=[]
out.append(f"fp_count={len(groups)}")
for h,names in sorted(groups.items(), key=lambda x: (-len(x[1]), x[0])):
    out.append(f"\n== FP {h} ({len(names)} files) ==")
    out.extend(["- "+n for n in names])
    out.append("---- sample ----")
    out.append((g/names[0]).read_text(errors="replace"))
Path("$EVID/header_fingerprint_groups.txt").write_text("\n".join(out), encoding="utf-8")
print("[OK] wrote header_fingerprint_groups.txt")
PY

# Marker hits: show first 120 lines + which keyword triggered
H="$latest_gate/html_marker_hits.txt"
if [ -f "$H" ]; then
  cp -f "$H" "$EVID/" || true
  grep -Ein 'DEBUG|TODO|TRACE|not available|N/A' "$H" | head -n 120 > "$EVID/marker_hits_top120.txt" || true
else
  echo "(no html_marker_hits.txt found)" > "$EVID/marker_hits_top120.txt"
fi

echo "[DONE] wrote $EVID/header_fingerprint_groups.txt and $EVID/marker_hits_top120.txt"
