#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_commercial_v2.js"
BK="$(ls -1t static/js/vsp_bundle_commercial_v2.js.bak_gate_rewrite_* 2>/dev/null | head -n1 || true)"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
[ -n "$BK" ] || { echo "[ERR] no bak_gate_rewrite_* found"; ls -1t static/js/vsp_bundle_commercial_v2.js.bak_* 2>/dev/null | head -n 10; exit 3; }

cp -f "$JS" "${JS}.bak_before_rollback_$(date +%Y%m%d_%H%M%S)"
cp -f "$BK" "$JS"
echo "[OK] restored $JS <= $BK"

command -v node >/dev/null 2>&1 && node --check "$JS" && echo "[OK] node --check passed" || true
systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] rollback applied. Now Ctrl+Shift+R /vsp5"
