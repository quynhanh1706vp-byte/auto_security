#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

DIR="$(ls -1dt out_ci/releases/RELEASE_UI_* | head -n1)"
TGZ="$(ls -1 "$DIR"/*.p541_official.tgz | head -n1)"
[ -n "$TGZ" ] || { echo "[ERR] missing *.p541_official.tgz in $DIR"; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

root_name="$(tar -tzf "$TGZ" | head -n1 | cut -d/ -f1)"
tar -xzf "$TGZ" -C "$TMP"
R="$TMP/$root_name"
[ -d "$R" ] || { echo "[ERR] extracted root missing"; exit 2; }

mkdir -p "$R/bin/legacy"

# allowlist within extracted release
keep_re='^(ui_gate\.sh|verify_release_and_customer_smoke\.sh|pack_release\.sh|ops\.sh|README_OFFICIAL_COMMANDS\.txt)$'

# move everything in bin/ except keep + official/
shopt -s nullglob
for f in "$R/bin/"*; do
  bn="$(basename "$f")"
  if [ "$bn" = "official" ]; then continue; fi
  if echo "$bn" | egrep -q "$keep_re"; then continue; fi
  mv -f "$f" "$R/bin/legacy/" || true
done

# extra: ensure legacy scripts not executable (avoid accidental run)
find "$R/bin/legacy" -type f -name "*.sh" -exec chmod -x {} \; 2>/dev/null || true

new_tgz="${TGZ%.tgz}.p543_clean.tgz"
tar -czf "$new_tgz" -C "$TMP" "$root_name"
echo "[OK] new tgz => $new_tgz"
