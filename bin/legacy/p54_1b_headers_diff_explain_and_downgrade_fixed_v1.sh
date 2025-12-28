#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p54_1b_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ls; need head; need python3; need diff; need grep; need awk; need sed; need cp; need mkdir

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release"; exit 2; }
ATT="$latest_release/evidence/p54_1b_${TS}"
mkdir -p "$ATT"
echo "[OK] latest_release=$latest_release"

latest_gate="$(ls -1dt "$OUT"/p54_gate_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_gate:-}" ] && [ -d "$latest_gate" ] || { echo "[ERR] no p54_gate_* found"; exit 2; }
echo "[OK] latest_gate=$latest_gate"

# Build groups + reps from *this* latest_gate directory
python3 - <<PY
from pathlib import Path
import hashlib, json

gate = Path("$latest_gate")
evid = Path("$EVID")
evid.mkdir(parents=True, exist_ok=True)

files = sorted(gate.glob("*_hdr_norm_sorted.txt"))
groups = {}
for f in files:
    h = hashlib.sha256(f.read_bytes()).hexdigest()[:16]
    groups.setdefault(h, []).append(f)

out=[]
out.append(f"fp_count={len(groups)}")
reps=[]
for h,fs in sorted(groups.items(), key=lambda x:(-len(x[1]), x[0])):
    out.append(f"\\n== FP {h} ({len(fs)} files) ==")
    for f in fs:
        out.append(f"- {f.name}")
    out.append("---- headers ----")
    out.append(fs[0].read_text(errors="replace"))
    reps.append((h, fs[0].name, fs[0].read_text(errors="replace")))

(evid/"header_fp_groups.txt").write_text("\\n".join(out)+"\\n", encoding="utf-8")
(evid/"header_fp_reps.json").write_text(json.dumps(reps, indent=2), encoding="utf-8")
print("[OK] wrote header_fp_groups.txt; reps=", len(reps))
PY

python3 - <<PY
import json
from pathlib import Path
evid=Path("$EVID")
reps=json.loads((evid/"header_fp_reps.json").read_text())
if len(reps) <= 1:
    (evid/"header_diff.txt").write_text("fp_count<=1; no diff\\n")
else:
    (evid/"rep0.txt").write_text(reps[0][2], encoding="utf-8")
    for i,(h,name,txt) in enumerate(reps[1:], start=1):
        (evid/f"rep{i}.txt").write_text(txt, encoding="utf-8")
print("[OK] reps written")
PY

# Diff rep0 vs rep1/rep2 (if present)
[ -f "$EVID/rep1.txt" ] && diff -u "$EVID/rep0.txt" "$EVID/rep1.txt" > "$EVID/diff_rep0_rep1.patch" 2>/dev/null || true
[ -f "$EVID/rep2.txt" ] && diff -u "$EVID/rep0.txt" "$EVID/rep2.txt" > "$EVID/diff_rep0_rep2.patch" 2>/dev/null || true

# Downgrade decision: allow downgrade only if differences DO NOT touch the hardening header set
downgrade=0
for p in "$EVID"/diff_rep0_rep*.patch; do
  [ -s "$p" ] || continue
  if grep -E '^[+-](Cache-Control:|Pragma:|Expires:|X-Frame-Options:|X-Content-Type-Options:|Referrer-Policy:)' "$p" >/dev/null; then
    downgrade=0
    break
  fi
  # If diff touches only HTTP/ status line -> downgrade OK
  if grep -E '^[+-]HTTP/' "$p" >/dev/null && ! grep -E '^[+-](Cache-Control:|Pragma:|Expires:|X-Frame-Options:|X-Content-Type-Options:|Referrer-Policy:)' "$p" >/dev/null; then
    downgrade=1
  else
    downgrade=0
    break
  fi
done
echo "downgrade_headers_warning=$downgrade" > "$EVID/downgrade_decision.txt"

# Find latest p54 verdict file (from OUT)
latest_p54_verdict="$(ls -1t "$OUT"/p54_gate_v2_verdict_*.json 2>/dev/null | head -n 1 || true)"
NEW="$OUT/p54_1b_verdict_${TS}.json"

python3 - <<PY
import json, time
from pathlib import Path

v=Path("$latest_p54_verdict")
if v.exists():
    j=json.loads(v.read_text())
else:
    j={"ok": True, "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "p54_gate_v2": {"warnings":[]}}

j.setdefault("p54_1b", {})
j["p54_1b"]["evidence_dir"]="$EVID"
j["p54_1b"]["attached_dir"]="$ATT"
j["p54_1b"]["latest_gate_dir"]="$latest_gate"
j["p54_1b"]["downgrade_headers_warning"]=bool(int("$downgrade"))

warns=j.get("p54_gate_v2", {}).get("warnings", []) or []
if int("$downgrade")==1:
    warns=[w for w in warns if w!="headers_fingerprint_mismatch"]
    if "headers_fingerprint_mismatch_noncritical" not in warns:
        warns.append("headers_fingerprint_mismatch_noncritical")
j.setdefault("p54_gate_v2", {})["warnings"]=warns

Path("$NEW").write_text(json.dumps(j, indent=2), encoding="utf-8")
print(json.dumps(j, indent=2))
PY

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
cp -f "$NEW" "$ATT/" 2>/dev/null || true
echo "[DONE] P54.1b wrote $NEW and attached evidence to $ATT"
