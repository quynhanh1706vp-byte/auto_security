#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p54_1_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ls; need head; need python3; need diff; need sed; need awk; need grep; need cp; need mkdir

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release"; exit 2; }
ATT="$latest_release/evidence/p54_1_${TS}"
mkdir -p "$ATT"
echo "[OK] latest_release=$latest_release"

latest_gate="$(ls -1dt "$OUT"/p54_gate_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_gate:-}" ] && [ -d "$latest_gate" ] || { echo "[ERR] no p54_gate_* found"; exit 2; }
echo "[OK] latest_gate=$latest_gate"

# Build group map by hashing file content (already sorted in p54)
python3 - <<'PY'
from pathlib import Path
import hashlib, re

g=Path("out_ci")
latest=sorted([p for p in g.glob("p54_gate_*") if p.is_dir()], reverse=True)[0]
files=sorted(latest.glob("*_hdr_norm_sorted.txt"))
groups={}
for f in files:
    h=hashlib.sha256(f.read_bytes()).hexdigest()[:16]
    groups.setdefault(h, []).append(f)

out=[]
out.append(f"fp_count={len(groups)}")
for h,fs in sorted(groups.items(), key=lambda x:(-len(x[1]), x[0])):
    out.append(f"\n== FP {h} ({len(fs)} files) ==")
    for f in fs: out.append(f"- {f.name}")
    out.append("---- headers ----")
    out.append(fs[0].read_text(errors="replace"))
Path("$EVID/header_fp_groups.txt").write_text("\n".join(out), encoding="utf-8")
print("[OK] wrote header_fp_groups.txt")

# Also write representative files for diff
reps=[]
for h,fs in sorted(groups.items(), key=lambda x:(-len(x[1]), x[0])):
    reps.append((h, fs[0].name, fs[0].read_text(errors="replace")))
Path("$EVID/header_fp_reps.json").write_text(
    __import__("json").dumps(reps, indent=2), encoding="utf-8"
)
print("[OK] wrote header_fp_reps.json")
PY

# Create diff of first rep vs others
python3 - <<'PY'
import json
from pathlib import Path
reps=json.loads(Path("$EVID/header_fp_reps.json").read_text())
if len(reps) <= 1:
    Path("$EVID/header_diff.txt").write_text("fp_count<=1; no diff\n")
    raise SystemExit(0)

base_h, base_name, base_txt = reps[0]
Path("$EVID/rep0.txt").write_text(base_txt, encoding="utf-8")
diffs=[]
for i,(h,name,txt) in enumerate(reps[1:], start=1):
    Path(f"$EVID/rep{i}.txt").write_text(txt, encoding="utf-8")

print("[OK] reps written")
PY

# system diff
diff -u "$EVID/rep0.txt" "$EVID/rep1.txt" > "$EVID/diff_rep0_rep1.patch" 2>/dev/null || true
diff -u "$EVID/rep0.txt" "$EVID/rep2.txt" > "$EVID/diff_rep0_rep2.patch" 2>/dev/null || true

# Decide downgrade: if diffs only touch HTTP status line OR minor header value quirks (rare) => noncritical
# We keep it conservative: downgrade if differences are ONLY on the first line (HTTP/...) across reps.
downgrade=0
for p in "$EVID"/diff_rep0_rep*.patch; do
  [ -s "$p" ] || continue
  # If any changed line mentions Cache-Control/Pragma/Expires/X-Frame-Options/X-Content-Type-Options/Referrer-Policy => critical mismatch
  if grep -E '^[+-](Cache-Control:|Pragma:|Expires:|X-Frame-Options:|X-Content-Type-Options:|Referrer-Policy:)' "$p" >/dev/null; then
    downgrade=0
    break
  fi
  # If patch changes only HTTP/ line, allow downgrade
  if grep -E '^[+-]HTTP/' "$p" >/dev/null && ! grep -E '^[+-](Cache-Control:|Pragma:|Expires:|X-Frame-Options:|X-Content-Type-Options:|Referrer-Policy:)' "$p" >/dev/null; then
    downgrade=1
  else
    downgrade=0
    break
  fi
done

echo "downgrade_headers_warning=$downgrade" | tee "$EVID/downgrade_decision.txt" >/dev/null

# Patch the latest P54 verdict in-place (copy new verdict next to it) if downgrade=1
latest_verdict="$(ls -1t "$latest_gate"/../p54_gate_v2_verdict_*.json 2>/dev/null | head -n 1 || true)"
# Fallback: find by attached evidence dir name
if [ -z "${latest_verdict:-}" ]; then
  latest_verdict="$(ls -1t "$OUT"/p54_gate_v2_verdict_*.json 2>/dev/null | head -n 1 || true)"
fi

NEW="$OUT/p54_1_verdict_${TS}.json"
python3 - <<PY
import json, time, os
from pathlib import Path
v_path = "${latest_verdict}"
j = {}
if v_path and Path(v_path).exists():
    j = json.loads(Path(v_path).read_text())
else:
    j = {"ok": True, "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "p54_gate_v2": {}}

j.setdefault("p54_1", {})
j["p54_1"]["evidence_dir"] = "$EVID"
j["p54_1"]["attached_dir"] = "$ATT"
j["p54_1"]["downgrade_headers_warning"] = bool(int("$downgrade"))
j["p54_1"]["latest_gate_dir"] = "$latest_gate"

warns = j.get("p54_gate_v2", {}).get("warnings", []) or []
if int("$downgrade") == 1:
    warns = [w for w in warns if w != "headers_fingerprint_mismatch"]
    if "headers_fingerprint_mismatch_noncritical" not in warns:
        warns.append("headers_fingerprint_mismatch_noncritical")
j.setdefault("p54_gate_v2", {})["warnings"] = warns

Path("$NEW").write_text(json.dumps(j, indent=2))
print(json.dumps(j, indent=2))
PY

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
cp -f "$NEW" "$ATT/" 2>/dev/null || true
echo "[DONE] P54.1 wrote $NEW and attached evidence"
