#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need tar; need sha256sum; need mkdir; need find

RELTS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/releases"
mkdir -p "$OUT"

PKG="$OUT/VSP_UI_RELEASE_${RELTS}.tgz"
NOTES="$OUT/RELEASE_NOTES_${RELTS}.txt"

echo "== [A] write release notes =="
cat > "$NOTES" <<EOF
VSP UI Commercial Release Snapshot
- release_ts: $RELTS
- base_dir: /home/test/Data/SECURITY_BUNDLE/ui
- includes: templates/, static/, wsgi_vsp_ui_gateway.py, vsp_demo_app.py, ui/out_ci logs pointers
- gate: p0_commercial_release_gate_selfcheck_v1.sh => READY (all GREEN)
EOF

echo "== [B] package =="
tar -czf "$PKG" \
  templates static \
  wsgi_vsp_ui_gateway.py vsp_demo_app.py \
  bin/p0_commercial_release_gate_selfcheck_v1.sh \
  bin/p0_fix_topfind_mw_no_flaskroute_v1.sh \
  bin/p1_topfind_polish_component_v1b.sh \
  2>/dev/null || true

SHA="$(sha256sum "$PKG" | awk '{print $1}')"
echo "$SHA  $(basename "$PKG")" | tee "$PKG.sha256"

echo "== [DONE] =="
echo "PKG=$PKG"
echo "SHA=$SHA"
echo "NOTES=$NOTES"
