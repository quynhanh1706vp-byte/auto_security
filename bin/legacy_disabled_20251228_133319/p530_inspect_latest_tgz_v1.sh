#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
RELROOT="$ROOT/out_ci/releases"
latest_dir="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n1 || true)"
[ -n "$latest_dir" ] || { echo "[FAIL] no release dir"; exit 2; }
tgz="$(ls -1 "$latest_dir"/*.tgz 2>/dev/null | head -n1 || true)"
[ -n "$tgz" ] || { echo "[FAIL] no tgz"; exit 2; }

echo "[P530] dir=$latest_dir"
echo "[P530] tgz=$tgz"

echo "== head tar list =="
tar -tzf "$tgz" | head -n 200

echo "== grep interesting =="
tar -tzf "$tgz" | grep -nE '(RELEASE_NOTES\.md|production\.env|systemd_unit\.template|logrotate_vsp-ui\.template|bin/p52[13]_.*\.sh|^VSP_UI_)' || true
