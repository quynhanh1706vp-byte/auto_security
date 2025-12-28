#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="official/pack_release.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p572_${TS}"
echo "[OK] backup => ${F}.bak_p572_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("official/pack_release.sh")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P572_STAGE_TAR_INCLUDE_ENTRYPOINTS"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# We replace the tar creation section with a stage-based tar that ensures entrypoints exist
# Find line that defines TGZ=... and the next tar -czf "$TGZ" .
m = re.search(r'(?ms)^\s*#\s*Build clean code tgz.*?\n.*?^TGZ=.*?\n.*?^\s*tar\s+.*?-czf\s+"\$TGZ"\s+\.\s*\n', s)
if not m:
    # fallback: find first tar -czf "$TGZ" .
    m = re.search(r'(?ms)^TGZ=.*?\n.*?^\s*tar\s+.*?-czf\s+"\$TGZ"\s+\.\s*\n', s)
    if not m:
        print("[ERR] cannot locate tar -czf \"$TGZ\" . block to patch")
        raise SystemExit(2)

block = m.group(0)

replacement = r'''# Build clean code tgz (stage-based, includes entrypoints)  # ''' + marker + r'''
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
( cd "$STAGE" && tar -czf "$TGZ" . )
echo "[OK] tgz=$TGZ size=$(wc -c <"$TGZ")"

sha256sum "$TGZ" | tee "$REL_DIR/SHA256SUMS.txt" >/dev/null

echo "== [4] sanity ship hygiene =="
if tar -tzf "$TGZ" | egrep -q '(^bin/p[0-9]|\.bak_|^out_ci/)'; then
  echo "[FAIL] hygiene: tgz still contains bin/p[0-9]* or *.bak_* or out_ci/"
  exit 12
fi
echo "[OK] hygiene clean"
'''

s2 = s[:m.start()] + replacement + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched official/pack_release.sh with stage tar include entrypoints")
PY

bash -n official/pack_release.sh
echo "[OK] bash -n ok"

# ensure bin/pack_release.sh points to official
ln -sf ../official/pack_release.sh bin/pack_release.sh
chmod +x official/pack_release.sh
echo "[OK] linked bin/pack_release.sh -> official/pack_release.sh"
