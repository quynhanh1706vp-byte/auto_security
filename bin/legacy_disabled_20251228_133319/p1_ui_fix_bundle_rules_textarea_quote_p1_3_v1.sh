#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_bundle_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_fixtextarea_${TS}"
echo "[BACKUP] ${F}.bak_fixtextarea_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_FIX_TEXTAREA_STYLE_QUOTE_P1_3_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# Fix the broken style attribute for rules-json textarea (missing closing quote)
# We match the line starting with style="... monospace; and replace it with a safe single-line style ending with ';">'
pat = r'style="width:100%;\s*min-height:240px;\s*font-family:ui-monospace,\s*SFMono-Regular,\s*Menlo,\s*Monaco,\s*Consolas,\s*monospace;'
m = re.search(pat, s)
if not m:
    print("[ERR] cannot find target textarea style pattern")
    raise SystemExit(2)

replacement = (
    f'<!-- {MARK} -->\\n'
    '          style="width:100%; min-height:240px; '
    'font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; '
    'padding:10px 12px; border-radius:12px; border:1px solid rgba(255,255,255,.08); '
    'background:rgba(0,0,0,.25); color:#e6edf3; line-height:1.35;">'
)

s2 = re.sub(pat, replacement, s, count=1)
p.write_text(s2, encoding="utf-8")
print("[OK] patched textarea style quote")
PY

if command -v node >/dev/null 2>&1; then
  echo "== node --check $F =="
  node --check "$F"
  echo "[OK] JS parse OK"
else
  echo "[WARN] node not installed; skip parse check"
fi

echo "[DONE] patched $F"
