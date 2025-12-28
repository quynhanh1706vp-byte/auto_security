#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="bin/verify_release_and_customer_smoke.sh"

# If it's a symlink, do nothing (we want to keep symlink to v3).
# If it's a wrapper file, patch it. If missing, create it as a symlink to v3.
if [ -L "$W" ]; then
  echo "[OK] $W is symlink => $(readlink -f "$W")"
  exit 0
fi

# Find v3 target
T="bin/p525_verify_release_and_customer_smoke_v3.sh"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
if [ -f "$W" ]; then
  cp -f "$W" "${W}.bak_p544_${TS}"
  echo "[OK] backup => ${W}.bak_p544_${TS}"
fi

cat > "$W" <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# [P544] stable wrapper: set defaults safely (no RELROOT nounset crash)
export RELROOT="${RELROOT:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases}"
exec bash bin/p525_verify_release_and_customer_smoke_v3.sh "$@"
WRAP

chmod +x "$W"
bash -n "$W"
echo "[OK] patched wrapper => $W"
