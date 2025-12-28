#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_rfallow_findingsfb_v4c_${TS}"
echo "[BACKUP] ${WSGI}.bak_rfallow_findingsfb_v4c_${TS}"

python3 - "$WSGI" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_RUN_FILE_ALLOW_FINDINGS_FALLBACK_V4C"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

lines=s.splitlines(True)

# locate def vsp_run_file_allow_v5():
def_i=None
for i,ln in enumerate(lines):
    if re.match(r'^\s*def\s+vsp_run_file_allow_v5\s*\(\s*\)\s*:', ln):
        def_i=i
        break
if def_i is None:
    print("[ERR] cannot find: def vsp_run_file_allow_v5():")
    raise SystemExit(2)

def_indent=len(lines[def_i]) - len(lines[def_i].lstrip(" "))

# find end of function block
end=len(lines)
for j in range(def_i+1, len(lines)):
    ln=lines[j]
    if ln.strip()=="":
        continue
    ind=len(ln) - len(ln.lstrip(" "))
    if ind==def_indent and re.match(r'^(def|@)\s', ln.lstrip()):
        end=j
        break

block="".join(lines[def_i:end])

# determine inner indent (first non-empty line after def)
inner_indent=" "*(def_indent+4)

# insert helper right after def line (before any code)
helper = (
    f"{inner_indent}# {MARK}\n"
    f"{inner_indent}def _vsp_rfa_norm(_r):\n"
    f"{inner_indent}    try:\n"
    f"{inner_indent}        if isinstance(_r, dict):\n"
    f"{inner_indent}            _f = _r.get('findings')\n"
    f"{inner_indent}            if not _f:\n"
    f"{inner_indent}                _it = _r.get('items')\n"
    f"{inner_indent}                _dt = _r.get('data')\n"
    f"{inner_indent}                if isinstance(_it, list) and _it:\n"
    f"{inner_indent}                    _r['findings'] = list(_it)\n"
    f"{inner_indent}                elif isinstance(_dt, list) and _dt:\n"
    f"{inner_indent}                    _r['findings'] = list(_dt)\n"
    f"{inner_indent}    except Exception:\n"
    f"{inner_indent}        pass\n"
    f"{inner_indent}    return _r\n"
)

# put helper after the def line
blk_lines=block.splitlines(True)
blk_lines.insert(1, helper)
block2="".join(blk_lines)

# wrap ALL return jsonify(...) / return flask.jsonify(...)
ret_pat=re.compile(r'(?m)^(\s*)return\s+((?:flask\.)?jsonify)\((.+)\)\s*$')
n=0
def repl(m):
    nonlocal n
    n += 1
    indent=m.group(1)
    fn=m.group(2)
    expr=m.group(3).strip()
    return f"{indent}return {fn}(_vsp_rfa_norm({expr}))\n"

block3, k = ret_pat.subn(repl, block2)
if k==0:
    print("[ERR] no return jsonify(...) found to wrap in vsp_run_file_allow_v5()")
    raise SystemExit(2)

out="".join(lines[:def_i]) + block3 + "".join(lines[end:])
p.write_text(out, encoding="utf-8")
print("[OK] patched:", MARK, "wrapped_returns=", k)
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"

echo "== verify findings fallback =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=3" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"findings_len=",len(j.get("findings") or []),"items_len=",len(j.get("items") or []),"data_len=",len(j.get("data") or []),"from=",j.get("from"))'
