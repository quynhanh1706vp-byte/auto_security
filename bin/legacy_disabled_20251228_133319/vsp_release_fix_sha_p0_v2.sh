#!/usr/bin/env bash
set -euo pipefail

REL="${1:-}"
if [ -z "${REL:-}" ]; then
  REL="$(ls -1dt /home/test/Data/SECURITY_BUNDLE/ui/out_ci/RELEASE_* 2>/dev/null | head -n1 || true)"
fi
[ -n "${REL:-}" ] || { echo "[ERR] cannot find RELEASE_* dir"; exit 2; }
[ -d "$REL" ] || { echo "[ERR] not a dir: $REL"; exit 2; }

cd "$REL"
echo "== FIX RELEASE SHA V2 =="
echo "[REL]=$REL"

TMP="$(mktemp /tmp/release_sha_XXXXXX)"
trap 'rm -f "$TMP" 2>/dev/null || true' EXIT

# rebuild manifest (exclude self + self-hash file)
find . -maxdepth 1 -type f \
  \( -name '*.tgz' -o -name '*.txt' -o -name '*.log' \) \
  ! -name 'RELEASE_SHA256SUMS.txt' \
  ! -name 'RELEASE_SHA256SUMS.self.txt' \
  -print0 \
| sort -z \
| xargs -0 sha256sum > "$TMP"

mv -f "$TMP" RELEASE_SHA256SUMS.txt
sha256sum RELEASE_SHA256SUMS.txt > RELEASE_SHA256SUMS.self.txt

sha256sum -c RELEASE_SHA256SUMS.txt
sha256sum -c RELEASE_SHA256SUMS.self.txt

echo "[OK] RELEASE_SHA256SUMS fixed + verified"
