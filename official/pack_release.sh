#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
REL_ID="$(date +%Y.%m.%d_%Y%m%d_%H%M%S)"
REL_DIR="out_ci/releases/RELEASE_UI_${REL_ID}"
mkdir -p "$REL_DIR"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need tar; need sha256sum; need grep; need ls; need head

echo "== [PACK] BASE=$BASE REL_DIR=$REL_DIR =="

# Hard gate: must PASS P550
echo "== [1] gate P550 (ui_gate) =="
bash official/ui_gate.sh

p550_latest="$(ls -1dt out_ci/p550_* 2>/dev/null | head -n1 || true)"
[ -n "$p550_latest" ] || { echo "[FAIL] no out_ci/p550_* found"; exit 9; }
[ -f "$p550_latest/RESULT.txt" ] || { echo "[FAIL] missing $p550_latest/RESULT.txt"; exit 9; }
grep -q '^PASS' "$p550_latest/RESULT.txt" || { echo "[FAIL] P550 not PASS"; exit 9; }
echo "[OK] P550 PASS: $p550_latest/RESULT.txt"

# Copy artifacts produced by P550 into release dir (these are the "commercial" exports)
echo "== [2] copy P550 artifacts into release dir =="
shopt -s nullglob
copied=0
for f in "$p550_latest"/*.html "$p550_latest"/*.pdf "$p550_latest"/*.tgz; do
  cp -f "$f" "$REL_DIR/"
  copied=$((copied+1))
done
echo "[OK] copied=$copied files"

# Create code TGZ with strict excludes (ship hygiene)
echo "== [3] build UI code TGZ (clean) =="
# Build clean code tgz (stage-based, includes entrypoints)  # VSP_P572_STAGE_TAR_INCLUDE_ENTRYPOINTS
echo "== [3] build UI code TGZ (clean, staged) =="

TGZ="$REL_DIR/VSP_UI_${REL_ID}.tgz"

EXCLUDES=(
  "--exclude=out_ci"
  "--exclude=bin/legacy"
  "--exclude=bin/p[0-9]*"
  "--exclude=*.bak_*"
  "--exclude=__pycache__"
  "--exclude=.pytest_cache"
  "--exclude=.mypy_cache"
  "--exclude=node_modules"
  "--exclude=.git"
)

STAGE="$REL_DIR/.stage_code"
rm -rf "$STAGE"
mkdir -p "$STAGE"

# Copy repo into stage (exclude noisy dirs)
# (prefer rsync if available)
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude 'out_ci' \
    --exclude 'bin/legacy' \
    --exclude 'bin/p[0-9]*' \
    --exclude '*.bak_*' \
    --exclude '__pycache__' \
    --exclude '.pytest_cache' \
    --exclude '.mypy_cache' \
    --exclude 'node_modules' \
    --exclude '.git' \
    ./ "$STAGE"/
else
  # fallback: tar pipe (still ok)
  tar "${EXCLUDES[@]}" -cf - . | (cd "$STAGE" && tar -xf -)
fi

# Ensure required commercial files are present in STAGE (dereference symlinks)
mkdir -p "$STAGE/bin" "$STAGE/config"
for ep in ui_gate.sh verify_release_and_customer_smoke.sh pack_release.sh ops.sh; do
  if [ ! -e "bin/$ep" ]; then
    echo "[FAIL] missing source entrypoint: bin/$ep"
    exit 11
  fi
  cp -fL "bin/$ep" "$STAGE/bin/$ep"
  chmod +x "$STAGE/bin/$ep" || true
done

for f in config/systemd_unit.template config/logrotate_vsp-ui.template config/production.env.example RELEASE_NOTES.md; do
  if [ -f "$f" ]; then
    mkdir -p "$STAGE/$(dirname "$f")" || true
    cp -fL "$f" "$STAGE/$f"
  fi
done

# Create tgz from stage
tar -C "$STAGE" -czf "$TGZ" .
echo "[OK] tgz=$TGZ size=$(wc -c <"$TGZ")"

sha256sum "$TGZ" | tee "$REL_DIR/SHA256SUMS.txt" >/dev/null

echo "== [4] sanity ship hygiene =="
if tar -tzf "$TGZ" | egrep -q '(^bin/p[0-9]|\.bak_|^out_ci/)'; then
  echo "[FAIL] hygiene: tgz still contains bin/p[0-9]* or *.bak_* or out_ci/"
  exit 12
fi
echo "[OK] hygiene clean"
echo "[OK] tgz=$TGZ size=$(wc -c <"$TGZ")"

sha256sum "$TGZ" | tee "$REL_DIR/SHA256SUMS.txt" >/dev/null

# Quick internal sanity: prove tgz is clean
echo "== [4] sanity ship hygiene =="
if tar -tzf "$TGZ" | egrep -q '(^bin/p|\.bak_|^out_ci/)'; then
  echo "[FAIL] hygiene: tgz still contains bin/p* or *.bak_* or out_ci/"
  exit 12
fi
echo "[OK] hygiene clean"

echo "== [DONE] release: $REL_DIR =="
