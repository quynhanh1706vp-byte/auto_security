#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v node >/dev/null 2>&1 || { echo "[WARN] node not found -> skip node --check"; }

JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fix_literalnl_${TS}"
echo "[BACKUP] ${JS}.bak_fix_literalnl_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

# Fix the literal "\n" sequence that was accidentally injected after a comment end.
# Replace only the first occurrence to avoid unintended changes.
needle = "*/\\n/*"
if needle in s:
    s2 = s.replace(needle, "*/\n/*", 1)
    p.write_text(s2, encoding="utf-8")
    print("[OK] fixed literal \\n -> real newline at file header")
else:
    print("[WARN] no literal '\\n' pattern found; nothing changed")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS"
  echo "[OK] node --check: $JS"
fi

echo
echo "[NEXT] Ctrl+Shift+R /vsp5"
echo "Expect: payload mismatch banner should disappear (unwrap active)."
