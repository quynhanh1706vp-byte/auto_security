#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
if [ -x bin/legacy/p559_commercial_preflight_audit_v2.sh ]; then
  echo "[preflight] using: bin/legacy/p559_commercial_preflight_audit_v2.sh"
  exec bash bin/legacy/p559_commercial_preflight_audit_v2.sh
fi
p559="$(ls -1t bin/legacy/p559_commercial_preflight_audit_v*.sh 2>/dev/null | head -n1 || true)"
[ -n "$p559" ] || { echo "[FAIL] no legacy p559 found under bin/legacy/"; exit 4; }
echo "[preflight] using: $p559"
exec bash "$p559"
