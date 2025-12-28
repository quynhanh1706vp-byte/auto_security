#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# 1) always gate first
bash official/ui_gate.sh

# 2) prefer v4 contract check if exists
if [ -x bin/legacy/p525_verify_release_and_customer_smoke_v4.sh ]; then
  echo "[verify] using: bin/legacy/p525_verify_release_and_customer_smoke_v4.sh"
  exec bash bin/legacy/p525_verify_release_and_customer_smoke_v4.sh
fi

# fallback: any legacy p525
p525="$(ls -1t bin/legacy/p525_verify_release_and_customer_smoke_v*.sh 2>/dev/null | head -n1 || true)"
[ -n "$p525" ] || { echo "[FAIL] no legacy p525 found"; exit 4; }
echo "[verify] using: $p525"
exec bash "$p525"
