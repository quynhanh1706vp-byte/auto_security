#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p565_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need tar; need sha256sum; need curl; need python3

echo "== [P565] BASE=$BASE TS=$TS ==" | tee "$OUT/run.log"

# -------------------------
# [1] Relock: move ALL bin/p*.sh to bin/legacy and chmod -x
# -------------------------
mkdir -p bin/legacy
moved=0
for f in bin/p*.sh; do
  [ -e "$f" ] || continue
  bn="$(basename "$f")"
  dest="bin/legacy/${bn}"
  if [ -e "$dest" ]; then
    dest="bin/legacy/${bn}.dup_${TS}"
  fi
  mv -f "$f" "$dest"
  chmod -x "$dest" || true
  echo "[OK] moved $f => $dest (chmod -x)" | tee -a "$OUT/run.log"
  moved=$((moved+1))
done
echo "[INFO] moved_count=$moved" | tee -a "$OUT/run.log"

# -------------------------
# [2] Patch official/pack_release.sh to pack from P550 artifacts (NOT legacy p39)
# -------------------------
mkdir -p official
F="official/pack_release.sh"
if [ -f "$F" ]; then
  cp -f "$F" "$F.bak_p565_${TS}"
  echo "[OK] backup $F => $F.bak_p565_${TS}" | tee -a "$OUT/run.log"
fi

cat > "$F" <<'EOS'
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
bash bin/ui_gate.sh

p550_latest="$(ls -1dt out_ci/p550_* 2>/dev/null | head -n1 || true)"
[ -n "$p550_latest" ] || { echo "[FAIL] no out_ci/p550_* found"; exit 9; }
[ -f "$p550_latest/RESULT.txt" ] || { echo "[FAIL] missing $p550_latest/RESULT.txt"; exit 9; }
grep -q '^PASS' "$p550_latest/RESULT.txt" || { echo "[FAIL] P550 not PASS"; exit 9; }
echo "[OK] P550 PASS: $p550_latest/RESULT.txt"

# Copy artifacts produced by P550 into release dir (these are the "commercial" exports)
echo "== [2] copy P550 artifacts into release dir =="
shopt -s nullglob
copied=0
for f in "$p550_latest"/report_*.html "$p550_latest"/report_*.pdf "$p550_latest"/support_bundle_*.tgz; do
  cp -f "$f" "$REL_DIR/"
  copied=$((copied+1))
done
echo "[OK] copied=$copied files"

# Create code TGZ with strict excludes (ship hygiene)
echo "== [3] build UI code TGZ (clean) =="
TGZ="$REL_DIR/VSP_UI_${REL_ID}.tgz"

EXCLUDES=(
  "--exclude=out_ci"
  "--exclude=bin/legacy"
  "--exclude=bin/p*"
  "--exclude=*.bak_*"
  "--exclude=__pycache__"
  "--exclude=.pytest_cache"
  "--exclude=.mypy_cache"
  "--exclude=node_modules"
  "--exclude=.git"
)

tar "${EXCLUDES[@]}" -czf "$TGZ" .
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
EOS

chmod +x "$F"
bash -n "$F"
echo "[OK] wrote $F" | tee -a "$OUT/run.log"

# Ensure bin/pack_release.sh symlink points to official (already in your setup, but enforce)
ln -sf official/pack_release.sh bin/pack_release.sh
chmod +x official/pack_release.sh

# -------------------------
# [3] Run pack + run preflight
# -------------------------
echo "== [P565] run pack_release ==" | tee -a "$OUT/run.log"
bash bin/pack_release.sh | tee -a "$OUT/pack_release.log" || true

echo "== [P565] run preflight (official alias) ==" | tee -a "$OUT/run.log"
bash bin/preflight_audit.sh | tee -a "$OUT/preflight.log" || true

echo "== [P565] DONE. Check logs under $OUT ==" | tee -a "$OUT/run.log"
