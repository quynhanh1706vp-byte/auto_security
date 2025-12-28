#!/usr/bin/env bash
set -euo pipefail
UI="/home/test/Data/SECURITY_BUNDLE/ui"
FLAG="${UI}/out_ci/PROD_FREEZE_ON"

mkdir -p "${UI}/out_ci"
date > "$FLAG"
chmod 444 "$FLAG" || true

echo "[OK] PROD FREEZE ON: $FLAG"
echo "[HINT] From now: DO NOT run patch_* scripts on this machine while in prod."
