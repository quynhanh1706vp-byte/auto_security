#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fixand_${TS}"
echo "[BACKUP] ${JS}.bak_fixand_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# Fix only inside our patch area if possible; otherwise do a safe, narrow replacement
# Target the exact buggy line: if(s!=="CRITICAL" and s!=="HIGH") continue;
fixed = 0
s2, n = re.subn(r'if\s*\(\s*s\s*!==\s*"CRITICAL"\s+and\s+s\s*!==\s*"HIGH"\s*\)\s*continue\s*;',
                r'if (s !== "CRITICAL" && s !== "HIGH") continue;',
                s)
if n:
    fixed += n
    s = s2

# Also handle any variant spacing/quotes:
s2, n = re.subn(r'if\s*\(\s*s\s*!==\s*([\'"])CRITICAL\1\s+and\s+s\s*!==\s*([\'"])HIGH\2\s*\)\s*continue\s*;',
                r'if (s !== "CRITICAL" && s !== "HIGH") continue;',
                s)
if n:
    fixed += n
    s = s2

p.write_text(s, encoding="utf-8")
print("[OK] fixed_count=", fixed)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS" || true; exit 2; }

echo "[DONE] Ctrl+Shift+R: ${VSP_UI_BASE:-http://127.0.0.1:8910}/vsp5"
echo "[CHECK] marker exists:"
grep -n "VSP_P1_DASH_MINICHARTS_FROM_FINDINGS_V1" "$JS" | head
