#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

pick_latest(){
  local pat="$1"
  ls -1t $pat 2>/dev/null | head -n 1 || true
}

# Best: pre-P67 backup (usually contains P66 only)
B="$(pick_latest "${F}.bak_p67_"*)"
if [ -z "${B:-}" ]; then
  # Next best: pre-P66 backup (might need reapply P66 if you want)
  B="$(pick_latest "${F}.bak_p66_"*)"
fi

if [ -z "${B:-}" ]; then
  echo "[ERR] no suitable backup found (bak_p67_* or bak_p66_*)."
  echo "      available backups:"
  ls -1 "${F}".bak_* 2>/dev/null || true
  exit 2
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p73_before_${TS}"
echo "[OK] backup current => ${F}.bak_p73_before_${TS}"

cp -f "$B" "$F"
echo "[OK] restored luxe from: $B"

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax fail after restore"; exit 2; }
fi

echo "[DONE] P73 restore complete. Hard refresh: Ctrl+Shift+R"
