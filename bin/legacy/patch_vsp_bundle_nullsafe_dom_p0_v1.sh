#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_nullsafe_${TS}"
echo "[BACKUP] $F.bak_nullsafe_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_BUNDLE_NULLSAFE_DOM_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

# Make these patterns null-safe:
#   document.querySelector(X).textContent = Y;
#   document.querySelector(X).innerHTML   = Y;
#   document.querySelector(X).value       = Y;
#   document.querySelector(X).disabled    = Y;
# (common offenders causing "Cannot set properties of null")
def wrap(prop):
    pat = re.compile(rf'document\.querySelector\((?P<sel>[^)]+)\)\.{prop}\s*=\s*(?P<rhs>[^;]+);')
    def repl(m):
        sel=m.group("sel")
        rhs=m.group("rhs")
        return f'(function(__el){{if(__el) __el.{prop}={rhs};}})(document.querySelector({sel}));'
    return pat, repl

for prop in ["textContent","innerHTML","value","disabled"]:
    pat, repl = wrap(prop)
    s = pat.sub(repl, s)

# Also null-safe: document.querySelector(X).classList.add/remove/toggle(...)
pat_cls = re.compile(r'document\.querySelector\((?P<sel>[^)]+)\)\.classList\.(?P<meth>add|remove|toggle)\((?P<args>[^)]+)\);')
def repl_cls(m):
    return f'(function(__el){{if(__el) __el.classList.{m.group("meth")}({m.group("args")});}})(document.querySelector({m.group("sel")}));'
s = pat_cls.sub(repl_cls, s)

s += f"\n/* {MARK} */\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

echo "== node --check =="
node --check "$F"
echo "[OK] node --check OK"

bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
echo "[NEXT] Ctrl+Shift+R http://127.0.0.1:8910/vsp4 (check console must be clean)"
