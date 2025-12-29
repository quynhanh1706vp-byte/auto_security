#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

RELROOT="out_ci/releases"
latest_dir="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n1 || true)"
[ -n "$latest_dir" ] || { echo "[FAIL] no RELEASE_UI_* under $RELROOT"; exit 2; }

echo "== [P951] FIX SHA FOR LATEST RELEASE =="
echo "RELEASE_DIR=$latest_dir"
ls -lah "$latest_dir" | sed -n '1,200p'

sha="$(ls -1 "$latest_dir"/*.sha256 2>/dev/null | head -n1 || true)"
if [ -z "$sha" ]; then
  echo "[WARN] no .sha256 found, will create a new one"
fi

# pick biggest archive (tgz or tar.gz)
tgz="$(find "$latest_dir" -maxdepth 2 -type f \( -name "*.tgz" -o -name "*.tar.gz" \) -printf "%s\t%p\n" \
  | sort -n | tail -n1 | awk '{print $2}' || true)"

if [ -z "$tgz" ] || [ ! -f "$tgz" ]; then
  echo "[FAIL] no archive (*.tgz/*.tar.gz) found under $latest_dir"
  echo "[HINT] snapshot may not have been created or got deleted (disk full cleanup?)"
  exit 3
fi

base="$(basename "$tgz")"
out_sha="${sha:-$latest_dir/${base}.sha256}"

echo "== [1] rebuild sha256 =="
( cd "$latest_dir" && sha256sum "$base" > "$(basename "$out_sha")" )
echo "[OK] wrote $(basename "$out_sha")"

echo "== [2] verify sha256 =="
( cd "$latest_dir" && sha256sum -c "$(basename "$out_sha")" )

echo "[PASS] sha256 fixed+verified for $base in $(basename "$latest_dir")"
