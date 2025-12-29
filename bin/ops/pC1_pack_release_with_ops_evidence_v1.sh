#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT_ROOT="out_ci/releases"
TS="$(date +%Y%m%d_%H%M%S)"
REL="$OUT_ROOT/RELEASE_UI_${TS}"
mkdir -p "$REL/evidence/ops"

# latest directory only (ignore files like run_evidence_index.json)
latest_dir_only() {
  local base="$1"
  [ -d "$base" ] || { echo ""; return 0; }
  find "$base" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" 2>/dev/null \
    | sort -nr | head -n1 | awk '{print $2}'
}

HC="$(latest_dir_only out_ci/ops_healthcheck)"
ST="$(latest_dir_only out_ci/ops_stamp)"
latest_dir_by_marker() {
  local base="$1"
  local marker="$2"
  [ -d "$base" ] || { echo ""; return 0; }
  # find marker files under immediate timestamp folders and pick newest
  local f
  f="$(find "$base" -mindepth 2 -maxdepth 2 -type f -name "$marker" -printf "%T@ %p\n" 2>/dev/null \
      | sort -nr | head -n1 | awk '{print $2}')"
  [ -n "$f" ] && dirname "$f" || echo ""
}

PF="$(latest_dir_by_marker out_ci/ops_proof PROOF.txt)"

echo "[INFO] healthcheck=$HC"
echo "[INFO] stamp=$ST"
echo "[INFO] proof=$PF"

# copy (best-effort)
[ -n "$HC" ] && cp -a "$HC" "$REL/evidence/ops/healthcheck" 2>/dev/null || true
[ -n "$ST" ] && cp -a "$ST" "$REL/evidence/ops/stamp" 2>/dev/null || true
[ -n "$PF" ] && cp -a "$PF" "$REL/evidence/ops/proof" 2>/dev/null || true

# evidence index
python3 - <<'PYY' > "$REL/evidence/EVIDENCE_INDEX.json"
import json
idx={
  "ops": {
    "healthcheck": "evidence/ops/healthcheck",
    "stamp": "evidence/ops/stamp",
    "proof": "evidence/ops/proof"
  },
  "notes": [
    "OPS evidence is copied from latest out_ci/* timestamp folders at packaging time.",
    "Artifacts are intentionally not committed to git (commercial hygiene)."
  ]
}
print(json.dumps(idx, indent=2))
PYY

cat > "$REL/RELEASE_NOTES.txt" <<'TXT'
RELEASE_UI (C-lite ISO/OPS pack)
- Includes latest OPS evidence (healthcheck/stamp/proof) under evidence/ops/
- Includes EVIDENCE_INDEX.json for audit navigation
TXT

TGZ="${REL}.tgz"
tar -C "$(dirname "$REL")" -czf "$TGZ" "$(basename "$REL")"
echo "[OK] packaged: $TGZ"
ls -lah "$TGZ"
