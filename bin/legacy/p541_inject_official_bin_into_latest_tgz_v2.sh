#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

REL_TGZ="$(ls -1dt out_ci/releases/RELEASE_UI_*/*.tgz | head -n1 || true)"
[ -n "$REL_TGZ" ] || { echo "[ERR] no release tgz found under out_ci/releases/RELEASE_UI_*/*.tgz"; exit 2; }

# required local entrypoints
req=(
  bin/official/ui_gate.sh
  bin/official/verify_release_and_customer_smoke.sh
  bin/official/pack_release.sh
  bin/official/ops.sh
  bin/ui_gate.sh
  bin/verify_release_and_customer_smoke.sh
  bin/pack_release.sh
  bin/ops.sh
)
for f in "${req[@]}"; do
  [ -e "$f" ] || { echo "[ERR] missing local file: $f"; exit 2; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[INFO] inject into: $REL_TGZ"
tar -xzf "$REL_TGZ" -C "$TMP"

# detect tgz root directory: take first top-level directory from tar listing
root_name="$(tar -tzf "$REL_TGZ" | head -n1 | cut -d/ -f1)"
[ -n "$root_name" ] || { echo "[ERR] cannot detect tgz root"; exit 2; }

root="$TMP/$root_name"
[ -d "$root" ] || { echo "[ERR] detected root not found after extract: $root"; exit 2; }

echo "[OK] detected_root=$root_name"

mkdir -p "$root/bin/official"
cp -a bin/official/ui_gate.sh "$root/bin/official/"
cp -a bin/official/verify_release_and_customer_smoke.sh "$root/bin/official/"
cp -a bin/official/pack_release.sh "$root/bin/official/"
cp -a bin/official/ops.sh "$root/bin/official/"

# shortcuts in the release
ln -sfn official/ui_gate.sh "$root/bin/ui_gate.sh"
ln -sfn official/verify_release_and_customer_smoke.sh "$root/bin/verify_release_and_customer_smoke.sh"
ln -sfn official/pack_release.sh "$root/bin/pack_release.sh"
ln -sfn official/ops.sh "$root/bin/ops.sh"

cat > "$root/bin/README_OFFICIAL_COMMANDS.txt" <<'TXT'
OFFICIAL COMMANDS (stable):
- bash bin/ui_gate.sh
- bash bin/verify_release_and_customer_smoke.sh
- bash bin/pack_release.sh
- bash bin/ops.sh smoke
TXT

# backup + repack (new file; keep original intact)
BAK="${REL_TGZ}.bak_before_p541v2_$(date +%Y%m%d_%H%M%S)"
cp -f "$REL_TGZ" "$BAK"

new_tgz="${REL_TGZ%.tgz}.p541_official.tgz"
tar -czf "$new_tgz" -C "$TMP" "$root_name"

echo "[OK] backup => $BAK"
echo "[OK] new tgz => $new_tgz"
