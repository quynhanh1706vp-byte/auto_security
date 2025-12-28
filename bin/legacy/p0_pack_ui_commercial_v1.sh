#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="/home/test/Data/SECURITY_BUNDLE/ui_pack"
PKG="$OUT/vsp_ui_commercial_${TS}"
TGZ="${PKG}.tgz"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need mkdir; need cp; need tar; need sha256sum; need date; need find

mkdir -p "$PKG"
mkdir -p "$OUT"

# core files
cp -f vsp_demo_app.py "$PKG/" 2>/dev/null || true
cp -f wsgi_vsp_ui_gateway.py "$PKG/" 2>/dev/null || true
cp -rf templates "$PKG/" 2>/dev/null || true
cp -rf static "$PKG/" 2>/dev/null || true
cp -rf bin "$PKG/" 2>/dev/null || true

# remove heavy/dev stuff if exists
rm -rf "$PKG/.venv" "$PKG/__pycache__" "$PKG/static/node_modules" 2>/dev/null || true
find "$PKG" -name "*.bak_*" -o -name "*.disabled_*" | head -n 200 | while read -r f; do rm -f "$f" 2>/dev/null || true; done

cat > "$PKG/PROOFNOTE.txt" <<EOF
VSP UI Commercial Snapshot
- Created: $TS
- Source: /home/test/Data/SECURITY_BUNDLE/ui
- Includes: vsp_demo_app.py, wsgi_vsp_ui_gateway.py, templates/, static/, bin/
- Expect 5 tabs: /vsp5 /runs /data_source /settings /rule_overrides
- C suite routes: /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides
EOF

tar -czf "$TGZ" -C "$OUT" "vsp_ui_commercial_${TS}"
sha256sum "$TGZ" > "${TGZ}.sha256"

echo "[OK] packed: $TGZ"
echo "[OK] sha256: ${TGZ}.sha256"
