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
cp -f "$JS" "${JS}.bak_syntaxfix_${TS}"
ok "backup: ${JS}.bak_syntaxfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_P0_FIX_LUXE_SYNTAX_RID_LATEST_TERNARY_V1"
if MARK in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

# Replace broken one-liner:
#   const r = await (__vspVisible()?fetch("/api/vsp/rid_latest", {cache:"no-store"});
# or similar, with safe guarded await expression (always syntactically valid).
pattern = re.compile(
    r'^(?P<indent>\s*)(?:const|let|var)\s+(?P<varname>[A-Za-z_$][\w$]*)\s*=\s*await\s*\(__vspVisible\(\)\?fetch\(\s*["\']/api/vsp/rid_latest["\']\s*,\s*\{cache:\s*["\']no-store["\']\}\s*\)\s*;\s*$',
    re.MULTILINE
)

def repl(m):
    ind=m.group("indent")
    var=m.group("varname")
    return (
        f'{ind}const {var} = await ((typeof __vspVisible==="function" && !__vspVisible())\n'
        f'{ind}  ? Promise.resolve(null)\n'
        f'{ind}  : fetch("/api/vsp/rid_latest", {{cache:"no-store"}}).catch(()=>null));'
    )

s2, n = pattern.subn(repl, s)

# If pattern didn't match (maybe minor variation), do a looser line-based fix.
if n == 0:
    lines=s.splitlines(True)
    out=[]
    fixed=0
    for line in lines:
        if 'fetch("/api/vsp/rid_latest"' in line and 'await (__vspVisible()?fetch' in line:
            # Replace whole line with safe guarded form, keep indent.
            ind=re.match(r'^(\s*)', line).group(1)
            out.append(
                f'{ind}const r = await ((typeof __vspVisible==="function" && !__vspVisible())\n'
                f'{ind}  ? Promise.resolve(null)\n'
                f'{ind}  : fetch("/api/vsp/rid_latest", {{cache:"no-store"}}).catch(()=>null));\n'
            )
            fixed += 1
        else:
            out.append(line)
    s2=''.join(out)
    n=fixed

if n == 0:
    # Don’t silently “fix nothing”
    raise SystemExit("[ERR] could not locate the broken rid_latest ternary line to patch")

s2 = s2.rstrip() + f"\n// {MARK}\n"
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched occurrences={n}")
PY

node --check "$JS" >/dev/null 2>&1 || { echo "[ERR] still SyntaxError in $JS"; node --check "$JS" || true; exit 2; }
ok "syntax OK now: $JS"

echo "== [QUICK PROOF] rid_latest lines =="
grep -n "rid_latest" -n "$JS" | head -n 20 || true

ok "DONE. Now HARD refresh browser (Ctrl+Shift+R) and confirm console has no SyntaxError."
