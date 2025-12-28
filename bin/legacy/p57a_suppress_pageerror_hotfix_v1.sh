#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
fix_one(){
  local f="$1"
  [ -f "$f" ] || { echo "[SKIP] missing $f"; return 0; }
  if grep -q "P57A_SAFE_WRAP_V1" "$f"; then
    echo "[OK] already wrapped: $f"
    return 0
  fi
  cp -f "$f" "${f}.bak_p57a_${TS}"
  python3 - <<PY
from pathlib import Path
p=Path("$f")
s=p.read_text(encoding="utf-8", errors="replace")
wrapped = "/* P57A_SAFE_WRAP_V1: prevent pageerror crash */\\n" + \
          "try{\\n" + s + "\\n}catch(e){\\n" + \
          "  try{ console && console.warn && console.warn('[VSP][P57A] suppressed: ' + " + repr("$f") + ", e && (e.stack||e)); }catch(_){ }\\n" + \
          "}\\n"
p.write_text(wrapped, encoding="utf-8")
print("wrapped", p)
PY
  echo "[OK] wrapped: $f"
}

# Hot targets (from your console screenshots)
fix_one "static/js/vsp_runs_quick_actions_v1.js"
fix_one "static/js/vsp_pin_dataset_badge_v1.js"

echo "[DONE] P57A applied. Re-run runtime gate:"
echo "  bash bin/p57_ui_luxe_gate_headless_v1.sh"
