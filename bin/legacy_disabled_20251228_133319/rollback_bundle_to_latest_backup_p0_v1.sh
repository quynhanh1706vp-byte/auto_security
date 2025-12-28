#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

B="$(ls -1t static/js/vsp_bundle_commercial_v1.js.bak_* 2>/dev/null | head -n1 || true)"
[ -n "${B:-}" ] || { echo "[ERR] no backup found: static/js/vsp_bundle_commercial_v1.js.bak_*"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_before_rollback_${TS}"
echo "[BACKUP] ${F}.bak_before_rollback_${TS}"

cp -f "$B" "$F"
echo "[RESTORE] $F <= $B"

# optional quick syntax check (won't block)
node --check "$F" >/dev/null 2>&1 && echo "[OK] node --check PASS" || echo "[WARN] node --check still FAIL (but we stop patching bundle anyway)"
