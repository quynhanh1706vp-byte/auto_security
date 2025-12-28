#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
SNAP="out_ci/snapshots/ui_safe_latest.tgz"
[ -f "$SNAP" ] || { echo "[ERR] missing $SNAP"; exit 2; }
tar -xzf "$SNAP" -C /home/test/Data/SECURITY_BUNDLE/ui --overwrite
echo "[OK] restored snapshot: $SNAP"
