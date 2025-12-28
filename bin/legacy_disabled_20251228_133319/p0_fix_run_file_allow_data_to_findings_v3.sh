#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_rfallow_data2find_${TS}"
echo "[BACKUP] ${WSGI}.bak_rfallow_data2find_${TS}"

python3 - "$WSGI" <<'PY'
import sys,re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P0_RUN_FILE_ALLOW_DATA_TO_FINDINGS_V3"
if marker in s:
    print("[OK] already patched v3")
    raise SystemExit(0)

route_idx = s.find("/api/vsp/run_file_allow")
if route_idx < 0:
    print("[ERR] cannot find /api/vsp/run_file_allow in wsgi")
    raise SystemExit(2)

# find def after the route
mdef = re.search(r'(?m)^[ \t]*def[ \t]+(?P<fn>[A-Za-z_]\w*)\s*\(', s[route_idx:])
if not mdef:
    print("[ERR] cannot find def after route")
    raise SystemExit(2)
def_start = route_idx + mdef.start()
fn = mdef.group("fn")

# find function end (next top-level def or next route decorator)
tail = s[def_start+1:]
mend = re.search(r'(?m)^[ \t]*(@application\.route\(|def[ \t]+[A-Za-z_]\w*\s*\()', tail)
func_end = (def_start+1 + mend.start()) if mend else len(s)

func = s[def_start:func_end]
if marker in func:
    print("[OK] already patched inside function")
    raise SystemExit(0)

# locate a dict var that receives ["data"] assignment
mdata = re.search(r'(?m)^(?P<ind>[ \t]*)(?P<var>[A-Za-z_]\w*)\[\s*[\'"]data[\'"]\s*\]\s*=\s*(?P<rhs>.+)\s*$', func)
if not mdata:
    # alternate: .setdefault("data", ...)
    mdata = re.search(r'(?m)^(?P<ind>[ \t]*)(?P<var>[A-Za-z_]\w*)\.setdefault\(\s*[\'"]data[\'"]\s*,', func)

if not mdata:
    # As fallback, patch right before the LAST return in this function, and try to detect payload var
    mret = list(re.finditer(r'(?m)^(?P<ind>[ \t]*)return\b.*$', func))
    if not mret:
        print("[ERR] cannot find a return line in run_file_allow function block")
        raise SystemExit(2)
    last = mret[-1]
    ind = last.group("ind")

    # try detect jsonify(var) in that return
    mvar = re.search(r'jsonify\(\s*([A-Za-z_]\w*)\s*\)', last.group(0))
    var = mvar.group(1) if mvar else None

    if not var:
        print("[ERR] cannot locate data assignment nor jsonify(var). Need a slightly different anchor.")
        # print a tiny hint (no spam)
        print("[HINT] run this to show key lines:\n  LC_ALL=C grep -nE \"run_file_allow|\\['data'\\]|setdefault\\('data'|return\" -n wsgi_vsp_ui_gateway.py | head -n 80")
        raise SystemExit(2)

    inject = (
        f"{ind}# {marker}\n"
        f"{ind}if isinstance({var}, dict):\n"
        f"{ind}    _f={var}.get('findings')\n"
        f"{ind}    _d={var}.get('data')\n"
        f"{ind}    if ((not isinstance(_f,list)) or (len(_f)==0)) and isinstance(_d,list) and len(_d)>0:\n"
        f"{ind}        {var}['findings']=_d\n"
    )
    func2 = func[:last.start()] + inject + func[last.start():]
else:
    ind = mdata.group("ind")
    var = mdata.group("var")
    # insert right AFTER the matched data line
    line_end = func.find("\n", mdata.end())
    if line_end < 0: line_end = len(func)
    line_end += 1

    inject = (
        f"{ind}# {marker}\n"
        f"{ind}if isinstance({var}, dict):\n"
        f"{ind}    _f={var}.get('findings')\n"
        f"{ind}    _d={var}.get('data')\n"
        f"{ind}    if ((not isinstance(_f,list)) or (len(_f)==0)) and isinstance(_d,list) and len(_d)>0:\n"
        f"{ind}        {var}['findings']=_d\n"
        f"{ind}    else:\n"
        f"{ind}        _i={var}.get('items')\n"
        f"{ind}        if ((not isinstance(_f,list)) or (len(_f)==0)) and isinstance(_i,list) and len(_i)>0:\n"
        f"{ind}            {var}['findings']=_i\n"
    )
    func2 = func[:line_end] + inject + func[line_end:]

s2 = s[:def_start] + func2 + s[func_end:]
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched {fn}: set findings from data/items when missing")
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" || true
echo "[OK] restarted (if service exists)"

grep -n "VSP_P0_RUN_FILE_ALLOW_DATA_TO_FINDINGS_V3" "$WSGI" | head -n 3 || true
