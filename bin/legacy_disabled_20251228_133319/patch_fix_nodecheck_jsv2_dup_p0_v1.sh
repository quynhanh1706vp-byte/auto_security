#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== FIX node --check path (jsv2.js) =="

# find offenders
bad="$(grep -RIn --include='*.sh' 'vsp_bundle_commercial_v2\.jsv2\.js' bin static 2>/dev/null || true)"
if [ -z "${bad:-}" ]; then
  echo "[OK] no bad path found: vsp_bundle_commercial_v2.js"
  exit 0
fi

echo "[FOUND]"
echo "$bad"

TS="$(date +%Y%m%d_%H%M%S)"
# patch all .sh under bin/ (safe)
while IFS= read -r f; do
  [ -f "$f" ] || continue
  cp -f "$f" "$f.bak_jsv2dup_${TS}"
  sed -i 's/vsp_bundle_commercial_v2\.jsv2\.js/vsp_bundle_commercial_v2\.js/g' "$f"
  echo "[PATCH] $f (backup: $f.bak_jsv2dup_${TS})"
done < <(echo "$bad" | awk -F: '{print $1}' | sort -u)

echo "== bash -n (sanity) =="
for f in $(echo "$bad" | awk -F: '{print $1}' | sort -u); do
  bash -n "$f"
done
echo "[OK] patched + bash -n OK"

# optional quick show remaining
echo "== re-check =="
grep -RIn --include='*.sh' 'vsp_bundle_commercial_v2\.jsv2\.js' bin static 2>/dev/null || echo "[OK] clean"
