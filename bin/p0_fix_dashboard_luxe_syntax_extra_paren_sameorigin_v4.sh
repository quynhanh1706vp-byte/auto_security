#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep

JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_sameorigin_paren_${TS}"
ok "backup: ${JS}.bak_sameorigin_paren_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_P0_FIX_LUXE_SYNTAX_EXTRA_PAREN_SAMEORIGIN_V4"
if MARK in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

before = s
# exact safest replacements
s = s.replace('same-origin"}))', 'same-origin"})')
s = s.replace("same-origin'}))", "same-origin'})")
s = s.replace('same-origin"} ))', 'same-origin"})')
s = s.replace("same-origin'} ))", "same-origin'})")

n = 0
# count delta by simple heuristic
n = before.count('same-origin"}))') - s.count('same-origin"}))')
n += before.count("same-origin'}))") - s.count("same-origin'}))")

if n <= 0:
    raise SystemExit("[ERR] did not find any 'same-origin\"}))' patterns to fix")

s = s.rstrip() + f"\n// {MARK} fixed={n}\n"
p.write_text(s, encoding="utf-8")
print(f"[OK] fixed={n}")
PY

node --check "$JS" >/dev/null 2>&1 || { echo "[ERR] still SyntaxError in $JS"; node --check "$JS" || true; exit 2; }
ok "syntax OK now: $JS"

echo "== [PROOF] any remaining same-origin\"})) ? =="
grep -n 'same-origin".*))' -n "$JS" | head -n 20 || true

ok "DONE. HARD refresh browser (Ctrl+Shift+R). Console must have NO SyntaxError."
