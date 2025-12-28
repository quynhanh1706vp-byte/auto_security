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
cp -f "$JS" "${JS}.bak_extrapar_${TS}"
ok "backup: ${JS}.bak_extrapar_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_P0_FIX_LUXE_SYNTAX_EXTRA_PAREN_FETCH_V3"
if MARK in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

def fix(api: str, text: str):
    # target: fetch(vspWithRid("/api/vsp/dash_kpis", ...), {credentials:"same-origin"}))
    # to:     fetch(vspWithRid("/api/vsp/dash_kpis", ...), {credentials:"same-origin"})
    pat = re.compile(
        r'fetch\(\s*(vspWithRid\(\s*["\']'+re.escape(api)+r'["\']\s*,\s*[^)]*\)\s*)\s*,\s*\{credentials\s*:\s*["\']same-origin["\']\}\s*\)\s*\)',
        re.DOTALL
    )
    def repl(m):
        inner=m.group(1)
        return f'fetch({inner}, {{credentials:"same-origin"}})'
    return pat.subn(repl, text)

s2=s
n_k=0; n_c=0
s2, n_k = fix("/api/vsp/dash_kpis", s2)
s2, n_c = fix("/api/vsp/dash_charts", s2)

# extra safety: if there is pattern "fetch(... {credentials:'same-origin'}))" without vspWithRid, fix too
pat_generic = re.compile(
    r'(fetch\(\s*[^,]+,\s*\{credentials\s*:\s*["\']same-origin["\']\}\s*\))\s*\)',
    re.DOTALL
)
s2, n_g = pat_generic.subn(r'\1', s2)

if (n_k+n_c+n_g) == 0:
    raise SystemExit("[ERR] no extra-paren fetch patterns matched; nothing patched")

s2 = s2.rstrip() + f"\n// {MARK} dash_kpis={n_k} dash_charts={n_c} generic={n_g}\n"
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched: dash_kpis={n_k} dash_charts={n_c} generic={n_g}")
PY

node --check "$JS" >/dev/null 2>&1 || { echo "[ERR] still SyntaxError in $JS"; node --check "$JS" || true; exit 2; }
ok "syntax OK now: $JS"

echo "== [PROOF] show dash_kpis fetch lines =="
grep -n '"/api/vsp/dash_kpis"' "$JS" | head -n 20 || true

ok "DONE. Now HARD refresh browser (Ctrl+Shift+R). Console must have NO SyntaxError."
