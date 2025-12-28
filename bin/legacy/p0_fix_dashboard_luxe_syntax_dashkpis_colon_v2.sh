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
cp -f "$JS" "${JS}.bak_dashkpis_syntaxfix_${TS}"
ok "backup: ${JS}.bak_dashkpis_syntaxfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_P0_FIX_LUXE_SYNTAX_DASHKPIS_COLON_V2"
if MARK in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

def fix_api(api: str, text: str):
    """
    Fix broken pattern:
      fetch(vspWithRid("/api/vsp/dash_kpis", ...), {credentials:"same-origin"}:Promise.resolve(null)))
    to:
      fetch(vspWithRid("/api/vsp/dash_kpis", ...), {credentials:"same-origin"})
    """
    # capture inside vspWithRid("/api/..", <expr>)
    pat = re.compile(
        r'fetch\(\s*(vspWithRid\(\s*["\']'+re.escape(api)+r'["\']\s*,\s*[^)]*\)\s*)\s*,\s*\{credentials\s*:\s*["\']same-origin["\']\}\s*:\s*Promise\.resolve\(null\)\s*\)\s*\)\s*\)',
        re.DOTALL
    )
    # also support {credentials:"same-origin"} without space
    pat2 = re.compile(
        r'fetch\(\s*(vspWithRid\(\s*["\']'+re.escape(api)+r'["\']\s*,\s*[^)]*\)\s*)\s*,\s*\{credentials\s*:\s*["\']same-origin["\']\}\s*:\s*Promise\.resolve\(null\)\s*\)\s*\)',
        re.DOTALL
    )

    def repl(m):
        inner=m.group(1)
        return f'fetch({inner}, {{credentials:"same-origin"}})'

    t, n = pat.subn(repl, text)
    if n == 0:
        t, n = pat2.subn(repl, text)
    return t, n

s2 = s
n1=0; n2=0

for api in ("/api/vsp/dash_kpis","/api/vsp/dash_charts"):
    s2, n = fix_api(api, s2)
    if api.endswith("dash_kpis"): n1 += n
    else: n2 += n

# Generic cleanup: if any "{credentials:'same-origin'}:Promise.resolve(null)" left, remove the ":Promise.resolve(null)" part.
s2, n3 = re.subn(
    r'(\{credentials\s*:\s*["\']same-origin["\']\})\s*:\s*Promise\.resolve\(null\)',
    r'\1',
    s2
)

if (n1+n2+n3) == 0:
    raise SystemExit("[ERR] pattern not found; nothing patched (need different fix)")

s2 = s2.rstrip() + f"\n// {MARK} dash_kpis={n1} dash_charts={n2} generic={n3}\n"
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched: dash_kpis={n1} dash_charts={n2} generic={n3}")
PY

node --check "$JS" >/dev/null 2>&1 || { echo "[ERR] still SyntaxError in $JS"; node --check "$JS" || true; exit 2; }
ok "syntax OK now: $JS"

echo "== [PROOF] show any remaining ':Promise.resolve(null)' =="
grep -n "Promise.resolve(null)" "$JS" | head -n 20 || true

ok "DONE. Now HARD refresh browser (Ctrl+Shift+R). Console must have NO SyntaxError."
