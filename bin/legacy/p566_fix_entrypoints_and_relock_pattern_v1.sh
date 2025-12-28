#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p566_${TS}"
mkdir -p "$OUT"
log(){ echo "$*" | tee -a "$OUT/run.log"; }

log "== [P566] fix entrypoints + relock pattern =="

mkdir -p bin/legacy official

# --- 1) Ensure official/pack_release.sh exists (if missing, recreate minimal gated pack) ---
if [ ! -f official/pack_release.sh ]; then
  log "[WARN] missing official/pack_release.sh => recreate"
  cat > official/pack_release.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
REL_ID="$(date +%Y.%m.%d_%Y%m%d_%H%M%S)"
REL_DIR="out_ci/releases/RELEASE_UI_${REL_ID}"
mkdir -p "$REL_DIR"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need tar; need sha256sum; need grep; need ls; need head; need curl; need python3

echo "== [PACK] BASE=$BASE REL_DIR=$REL_DIR =="

# Hard gate P550
bash bin/ui_gate.sh
p550_latest="$(ls -1dt out_ci/p550_* 2>/dev/null | head -n1 || true)"
[ -n "$p550_latest" ] || { echo "[FAIL] no out_ci/p550_* found"; exit 9; }
[ -f "$p550_latest/RESULT.txt" ] || { echo "[FAIL] missing $p550_latest/RESULT.txt"; exit 9; }
grep -q '^PASS' "$p550_latest/RESULT.txt" || { echo "[FAIL] P550 not PASS"; exit 9; }
echo "[OK] P550 PASS: $p550_latest/RESULT.txt"

# Copy artifacts from P550 into release dir
shopt -s nullglob
for f in "$p550_latest"/report_*.html "$p550_latest"/report_*.pdf "$p550_latest"/support_bundle_*.tgz; do
  cp -f "$f" "$REL_DIR/"
done

# Build clean code tgz
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
tar "${EXCLUDES[@]}" -czf "$TGZ" .
sha256sum "$TGZ" > "$REL_DIR/SHA256SUMS.txt"

# sanity
if tar -tzf "$TGZ" | egrep -q '(^bin/p[0-9]|\.bak_|^out_ci/)'; then
  echo "[FAIL] hygiene: tgz still contains p[0-9]* or *.bak_* or out_ci/"
  exit 12
fi

echo "[OK] DONE: $REL_DIR"
EOS
  chmod +x official/pack_release.sh
  bash -n official/pack_release.sh
  log "[OK] recreated official/pack_release.sh"
else
  log "[OK] official/pack_release.sh exists"
fi

# --- 2) Restore bin/pack_release.sh as symlink to official ---
ln -sf ../official/pack_release.sh bin/pack_release.sh
chmod +x official/pack_release.sh
log "[OK] restored bin/pack_release.sh -> official/pack_release.sh"

# --- 3) Restore bin/preflight_audit.sh wrapper calling latest legacy p559 ---
p559="$(ls -1t bin/legacy/p559_commercial_preflight_audit_v*.sh 2>/dev/null | head -n1 || true)"
if [ -z "$p559" ]; then
  log "[WARN] no legacy p559 found; preflight wrapper will only hint"
  cat > bin/preflight_audit.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
echo "[FAIL] legacy p559 not found under bin/legacy/"
exit 4
EOS
else
  cat > bin/preflight_audit.sh <<EOS
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
echo "[preflight] using: $p559"
bash "$p559"
EOS
fi
chmod +x bin/preflight_audit.sh
log "[OK] restored bin/preflight_audit.sh"

# --- 4) Write safe relock script (numeric-only) for future use ---
cat > bin/relock_numeric_only.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p bin/legacy
moved=0
for f in bin/p[0-9]*.sh; do
  [ -e "$f" ] || continue
  bn="$(basename "$f")"
  dest="bin/legacy/$bn"
  [ ! -e "$dest" ] || dest="bin/legacy/${bn}.dup_${TS}"
  mv -f "$f" "$dest"
  chmod -x "$dest" || true
  echo "[OK] moved $f => $dest"
  moved=$((moved+1))
done
echo "[OK] moved_count=$moved"
EOS
chmod +x bin/relock_numeric_only.sh
log "[OK] wrote bin/relock_numeric_only.sh (SAFE pattern p[0-9]*.sh only)"

# --- 5) Quick smoke: show entrypoints, then run pack + preflight ---
ls -l bin/ui_gate.sh bin/verify_release_and_customer_smoke.sh bin/pack_release.sh bin/ops.sh bin/preflight_audit.sh \
  | tee "$OUT/entrypoints_ls.txt" || true

log "== [P566] run pack_release =="
bash bin/pack_release.sh | tee -a "$OUT/pack_release.log" || true

log "== [P566] run preflight =="
bash bin/preflight_audit.sh | tee -a "$OUT/preflight.log" || true

log "== [P566] DONE OUT=$OUT =="
echo "OUT=$OUT"
