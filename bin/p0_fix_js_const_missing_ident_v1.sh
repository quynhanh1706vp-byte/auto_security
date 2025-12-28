#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp
command -v node >/dev/null 2>&1 || { echo "[ERR] missing: node (need node --check)"; exit 2; }
command -v systemctl >/dev/null 2>&1 || true

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_fix_missing_ident_${TS}"
echo "[BACKUP] ${JS}.bak_fix_missing_ident_${TS}"

echo "== [1] node --check BEFORE =="
node --check "$JS" 2>&1 | head -n 30 || true

python3 - "$JS" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

# Fix lines like:
#   const = ( ... );
#   let   = foo;
# Strategy:
# - If "rid" is already declared earlier in the file -> replace "const =" with "rid ="
# - Else -> replace with "const rid ="
decl_rid = re.search(r'(?m)^\s*(?:const|let|var)\s+rid\s*=', s) is not None

def repl(m):
    kw = m.group(1)
    if decl_rid:
        return m.group(0).replace(m.group(0), "rid = ")
    # no rid declared anywhere: declare it safely
    return "const rid = "

# Replace ALL bad declarations at line start
bad_pat = re.compile(r'(?m)^\s*(const|let|var)\s*=\s*')
s2, n = bad_pat.subn(repl, s)

# Also fix cases with accidental double spaces "const    ="
# (covered by regex) + keep file unchanged otherwise.
p.write_text(s2, encoding="utf-8")
print(f"[PATCH] bad_missing_ident_fixed={n} rid_declared_preexisted={decl_rid}")
PY

echo "== [2] node --check AFTER =="
node --check "$JS"
echo "[OK] JS syntax clean"

echo "== [3] Restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.5
  sudo systemctl --no-pager --full status "$SVC" | head -n 25 || true
fi

echo "[DONE] Hard refresh (Ctrl+F5) on /c/dashboard then watch Console."
