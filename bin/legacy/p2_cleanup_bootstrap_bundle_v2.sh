#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
F1="static/js/vsp_bundle_tabs5_v1.js"
F2="static/js/vsp_tabs4_autorid_v1.js"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need cp; need date
command -v node >/dev/null 2>&1 || { echo "[ERR] missing node (need node --check)"; exit 2; }

fix(){
  local f="$1"
  [ -f "$f" ] || { echo "[WARN] missing $f (skip)"; return 0; }
  cp -f "$f" "${f}.bak_cleanup_${TS}"

  python3 - <<PY
from pathlib import Path
import re

p=Path("$f")
s=p.read_text(encoding="utf-8", errors="replace")
orig=s

# (1) Remove legacy pin badge v1 loader (keep v2 only)
s=re.sub(r'(?ms)^\(function\(\)\{try\{if\(window\.__VSP_PIN_BADGE_V1.*?\}\}\)\(\);\s*\n','',s)

# (2) Remove dangerous monkey-patch block that overrides Element.prototype.appendChild
s=re.sub(r'(?ms)^//\s*===\s*CIO:\s*hard-block luxe outside\s*/vsp5.*?\(function\(\)\{.*?\}\)\(\);\s*\n','',s)

# Also remove any remaining mention line-by-line (fallback)
s=re.sub(r'(?m)^.*__VSP_PIN_BADGE_V1.*\n','',s)

if s!=orig:
    p.write_text(s, encoding="utf-8")
    print("[OK] cleaned:", p)
else:
    print("[OK] no change:", p)
PY

  node --check "$f" >/dev/null
  echo "[OK] node --check $f"
}

fix "$F1"
fix "$F2"
echo "[DONE] cleaned bootstrap (removed pin v1 + removed monkey-patch). Ctrl+F5."
