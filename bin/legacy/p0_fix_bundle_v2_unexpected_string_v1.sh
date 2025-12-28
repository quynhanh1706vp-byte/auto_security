#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fix_unexpected_string_${TS}"
echo "[BACKUP] ${JS}.bak_fix_unexpected_string_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_FIX_BUNDLE_V2_UNEXPECTED_STRING_V1"
if marker not in s:
    s = "/* %s */\n" % marker + s

# Fix the broken qs({ ... }) object where stray strings were inserted.
# Example broken:
# qs({rid:S.lastRid, path:"reports/findings_unified.html", "run_gate_summary.json", "reports/run_gate_summary.json", "reports/run_gate.json"})
#
# We normalize it to:
# qs({rid:S.lastRid, path:"reports/findings_unified.html"})
#
pat = re.compile(
    r'qs\(\{\s*rid\s*:\s*S\.lastRid\s*,\s*path\s*:\s*"reports/findings_unified\.html"\s*,\s*[^}]*?\}\)',
    flags=re.M
)

s2, n = pat.subn('qs({rid:S.lastRid, path:"reports/findings_unified.html"})', s)

# Also catch variants with path: '...' or whitespace/newlines
pat2 = re.compile(
    r'qs\(\{\s*rid\s*:\s*S\.lastRid\s*,\s*path\s*:\s*[\'"]reports/findings_unified\.html[\'"]\s*,\s*[^}]*?\}\)',
    flags=re.M
)
s2, n2 = pat2.subn('qs({rid:S.lastRid, path:"reports/findings_unified.html"})', s2)

if n + n2 == 0:
    # As a fallback, fix the specific window.open line if present
    s2b, n3 = re.subn(
        r'window\.open\(`\/api\/vsp\/run_file_allow\?\$\{qs\(\{rid:S\.lastRid,\s*path:"reports\/findings_unified\.html"[^}]*\}\)\}\`,\s*"_blank"\);\s*',
        'window.open(`/api/vsp/run_file_allow?${qs({rid:S.lastRid, path:"reports/findings_unified.html"})}`, "_blank");\n',
        s2,
        flags=re.M
    )
    s2 = s2b
    n = n + n3

p.write_text(s2, encoding="utf-8")
print("[OK] rewrote broken qs(...) object(s):", (n + n2))
PY

echo "== node --check (must be OK) =="
node --check "$JS" && echo "[OK] node --check passed: $JS"

echo
echo "NEXT: Ctrl+F5 /vsp5 (hard refresh)."
