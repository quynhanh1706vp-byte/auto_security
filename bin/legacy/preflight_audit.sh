#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
echo "[preflight] using: bin/legacy/p559_commercial_preflight_audit_v1.sh"
bash "bin/legacy/p559_commercial_preflight_audit_v1.sh"

