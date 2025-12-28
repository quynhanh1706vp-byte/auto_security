#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

REL_TGZ="$(ls -1dt out_ci/releases/RELEASE_UI_*/*.tgz | head -n1 || true)"
[ -n "$REL_TGZ" ] || { echo "[ERR] no release tgz found under out_ci/releases/RELEASE_UI_*/*.tgz"; exit 2; }

# required local entrypoints
for f in bin/official/ui_gate.sh bin/official/verify_release_and_customer_smoke.sh bin/official/pack_release.sh bin/official/ops.sh; do
  [ -e "$f" ] || { echo "[ERR] missing local official entrypoint: $f"; exit 2; }
done
for f in bin/ui_gate.sh bin/verify_release_and_customer_smoke.sh bin/pack_release.sh bin/ops.sh; do
  [ -e "$f" ] || { echo "[ERR] missing local shortcut: $f"; exit 2; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[INFO] inject into: $REL_TGZ"
tar -xzf "$REL_TGZ" -C "$TMP"

root="$(find "$TMP" -maxdepth 2 -type d -name "RELEASE_UI_*" | head -n1 || true)"
[ -n "$root" ] || { echo "[ERR] cannot find RELEASE_UI_* folder inside tgz"; exit 2; }

mkdir -p "$root/bin/official"
cp -a bin/official/ui_gate.sh "$root/bin/official/"
cp -a bin/official/verify_release_and_customer_smoke.sh "$root/bin/official/"
cp -a bin/official/pack_release.sh "$root/bin/official/"
cp -a bin/official/ops.sh "$root/bin/official/"

# shortcuts (symlinks)
( cd "$root" && \
  ln -sfn official/ui_gate.sh bin/ui_gate.sh && \
  ln -sfn official/verify_release_and_customer_smoke.sh bin/verify_release_and_customer_smoke.sh && \
  ln -sfn official/pack_release.sh bin/pack_release.sh && \
  ln -sfn official/ops.sh bin/ops.sh )

# add a tiny README for customers
cat > "$root/bin/README_OFFICIAL_COMMANDS.txt" <<'TXT'
OFFICIAL COMMANDS (stable):
- bash bin/ui_gate.sh
- bash bin/verify_release_and_customer_smoke.sh
- bash bin/pack_release.sh
- bash bin/ops.sh smoke
TXT

# backup + repack
BAK="${REL_TGZ}.bak_before_p541_$(date +%Y%m%d_%H%M%S)"
cp -f "$REL_TGZ" "$BAK"

new_tgz="${REL_TGZ%.tgz}.p541_official.tgz"
tar -czf "$new_tgz" -C "$TMP" "$(basename "$root")"

echo "[OK] backup => $BAK"
echo "[OK] new tgz => $new_tgz"
