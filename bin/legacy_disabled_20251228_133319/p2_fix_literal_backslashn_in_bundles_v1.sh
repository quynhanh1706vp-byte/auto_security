#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
F1="static/js/vsp_bundle_tabs5_v1.js"
F2="static/js/vsp_tabs4_autorid_v1.js"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp
command -v node >/dev/null 2>&1 || { echo "[ERR] missing node (need node --check)"; exit 2; }

fix_one(){
  local f="$1"
  [ -f "$f" ] || { echo "[WARN] missing $f (skip)"; return 0; }
  cp -f "$f" "${f}.bak_fix_backslashn_${TS}"

  python3 - <<PY
from pathlib import Path
import re

p=Path("$f")
s=p.read_text(encoding="utf-8", errors="replace")

# Fix only the bad injected pattern: literal backslash-n used as a newline.
# Replace \n ONLY when it is used between JS statements (followed by ( / try / function / //).
s2 = s
s2 = re.sub(r'\\\\n(?=\\()', '\n', s2)
s2 = re.sub(r'\\\\n(?=try\\{)', '\n', s2)
s2 = re.sub(r'\\\\n(?=function\\b)', '\n', s2)
s2 = re.sub(r'\\\\n(?=//)', '\n', s2)

if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print("[OK] fixed literal \\\\n -> newline in", p)
else:
    print("[OK] no literal \\\\n to fix in", p)
PY

  node --check "$f" >/dev/null
  echo "[OK] node --check $f"
}

fix_one "$F1"
fix_one "$F2"

echo "[DONE] bundles fixed. Ctrl+F5 once."
