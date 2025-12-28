#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need awk; need grep; need sed; need python3; need cp; need mkdir

latest_gate="$(ls -1dt "$OUT"/p51_gate_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_gate:-}" ] && [ -d "$latest_gate" ] || { echo "[ERR] no p51_gate folder found"; exit 2; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found under $RELROOT"; exit 2; }

ATT="$latest_release/evidence/$(basename "$latest_gate")"
mkdir -p "$ATT"

VER="$OUT/p51_verdict_fixed_${TS}.json"

python3 - <<PY
import json, time, re
from pathlib import Path

gate = Path("$latest_gate")
reasons=[]
warns=[]

# 1) tabs: require 200
ts = gate/"tab_status.txt"
if ts.exists():
    for line in ts.read_text(errors="replace").splitlines():
        parts=line.split("|")
        if len(parts) >= 3:
            name,path,code = parts[0],parts[1],parts[2]
            if code != "200":
                reasons.append(f"tab_{name}_http_{code}")
else:
    reasons.append("missing_tab_status")

# 2) static sample: require 0 non-200
ss = gate/"static_sample_summary.txt"
bad=0
if ss.exists():
    m=re.search(r"bad_static_sample=(\d+)", ss.read_text(errors="replace"))
    if m: bad=int(m.group(1))
    if bad>0:
        reasons.append(f"static_sample_non200_{bad}")
else:
    warns.append("missing_static_sample_summary")

# 3) header fingerprints mismatch = warn
hf = gate/"header_fingerprints.txt"
if hf.exists():
    fps=set()
    for line in hf.read_text(errors="replace").splitlines():
        if "\t" in line:
            fps.add(line.split("\t",1)[1].strip())
    if len(fps)>1:
        warns.append("headers_fingerprint_mismatch")
else:
    warns.append("missing_header_fingerprints")

# 4) markers warn (soft)
mh = gate/"html_marker_hits.txt"
if mh.exists() and mh.stat().st_size>0:
    warns.append("html_markers_found")

ok = (len(reasons)==0)
verdict = {
  "ok": ok,
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "p51_fixed": {
    "gate_dir": str(gate),
    "latest_release": "$latest_release",
    "reasons": reasons,
    "warnings": warns
  }
}
print(json.dumps(verdict, indent=2))
Path("$VER").write_text(json.dumps(verdict, indent=2))
PY

# attach everything into release evidence (keep the original gate evidence + add fixed verdict)
cp -f "$VER" "$ATT/" 2>/dev/null || true

echo "[OK] latest_gate=$latest_gate"
echo "[OK] wrote $VER"
echo "[OK] attached to $ATT/$(basename "$VER")"

# exit code based on ok
python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); sys.exit(0 if j.get("ok") else 2)' "$VER"
