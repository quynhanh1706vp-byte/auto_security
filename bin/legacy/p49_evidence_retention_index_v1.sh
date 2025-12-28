#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"
REL_ROOT="$OUT/releases"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
mkdir -p "$REL_ROOT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need find; need sort; need head; need sha256sum; need python3; need ls

TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p49_evidence_${TS}.txt"
ok(){ echo "[OK] $*" | tee -a "$LOG"; }

echo "== [P49] evidence retention + index ==" | tee "$LOG"
echo "[INFO] REL_ROOT=$REL_ROOT RETENTION_DAYS=$RETENTION_DAYS" | tee -a "$LOG"

# 1) Retention: delete releases older than N days (by mtime)
if [ "$RETENTION_DAYS" -gt 0 ]; then
  old="$(find "$REL_ROOT" -maxdepth 1 -type d -name 'RELEASE_UI_*' -mtime "+$RETENTION_DAYS" -print | wc -l | tr -d ' ')"
  if [ "$old" != "0" ]; then
    find "$REL_ROOT" -maxdepth 1 -type d -name 'RELEASE_UI_*' -mtime "+$RETENTION_DAYS" -print -exec rm -rf {} \;
    ok "retention: removed old releases count=$old"
  else
    ok "retention: nothing to remove"
  fi
fi

# 2) Refresh SHA256SUMS for each release folder
rels=( $(ls -1d "$REL_ROOT"/RELEASE_UI_* 2>/dev/null | sort || true) )
ok "release_count=${#rels[@]}"

for d in "${rels[@]}"; do
  [ -d "$d" ] || continue
  ( cd "$d"
    # exclude huge or transient if needed; currently keep all
    find . -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS.txt
  )
  ok "sha: $(basename "$d")/SHA256SUMS.txt"
done

# 3) Build evidence index
latest_verdict="$(ls -1t "$OUT"/p46_verdict_*.json 2>/dev/null | head -n 1 || true)"
latest_snapshot="$(ls -1t "$OUT"/p47_golden_snapshot_*.json 2>/dev/null | head -n 1 || true)"

python3 - <<PY > "$REL_ROOT/EVIDENCE_INDEX.json"
import json, os, glob
rel_root="${REL_ROOT}"
rels=sorted(glob.glob(os.path.join(rel_root,"RELEASE_UI_*")))
items=[]
for r in rels:
    hand=os.path.join(r,"HANDOVER.md")
    sha=os.path.join(r,"SHA256SUMS.txt")
    items.append({
        "release_dir": r,
        "handover": hand if os.path.exists(hand) else "",
        "sha256sums": sha if os.path.exists(sha) else "",
    })
j={
  "ok": True,
  "generated_at": "${TS}",
  "retention_days": int("${RETENTION_DAYS}"),
  "latest_verdict": "${latest_verdict}",
  "latest_snapshot": "${latest_snapshot}",
  "releases": items,
}
print(json.dumps(j, indent=2))
PY

ok "wrote: $REL_ROOT/EVIDENCE_INDEX.json"
ok "log: $LOG"
