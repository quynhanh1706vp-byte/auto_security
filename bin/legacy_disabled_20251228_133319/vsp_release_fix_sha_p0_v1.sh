#!/usr/bin/env bash
set -euo pipefail

REL="${1:-}"
if [ -z "${REL:-}" ]; then
  REL="$(ls -1dt /home/test/Data/SECURITY_BUNDLE/ui/out_ci/RELEASE_* 2>/dev/null | head -n1 || true)"
fi
[ -n "${REL:-}" ] || { echo "[ERR] cannot find RELEASE_* dir"; exit 2; }
[ -d "$REL" ] || { echo "[ERR] not a dir: $REL"; exit 2; }

cd "$REL"
echo "== FIX RELEASE SHA =="
echo "[REL]=$REL"

# (A) rebuild manifest without self-reference
TMP=".__sha_tmp_$$.txt"
: > "$TMP"

# include tgz/txt/log except RELEASE_SHA256SUMS itself
find . -maxdepth 1 -type f \( -name '*.tgz' -o -name '*.txt' -o -name '*.log' \) \
  ! -name 'RELEASE_SHA256SUMS.txt' -print0 \
| sort -z \
| xargs -0 sha256sum > "$TMP"

mv -f "$TMP" RELEASE_SHA256SUMS.txt

# (B) optional: hash the manifest in a separate file (no recursion)
sha256sum RELEASE_SHA256SUMS.txt > RELEASE_SHA256SUMS.self.txt

# (C) verify
sha256sum -c RELEASE_SHA256SUMS.txt
sha256sum -c RELEASE_SHA256SUMS.self.txt

echo "[OK] RELEASE_SHA256SUMS fixed + verified"
