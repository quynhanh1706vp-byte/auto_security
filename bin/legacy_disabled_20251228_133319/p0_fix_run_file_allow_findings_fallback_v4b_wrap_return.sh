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
cp -f "$WSGI" "${WSGI}.bak_rfallow_findingsfb_v4b_${TS}"
echo "[BACKUP] ${WSGI}.bak_rfallow_findingsfb_v4b_${TS}"

python3 - "$WSGI" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_RUN_FILE_ALLOW_FINDINGS_FALLBACK_V4B"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

lines=s.splitlines(True)

# 1) locate def vsp_run_file_allow_v5():
def_i=None
for i,ln in enumerate(lines):
    if re.match(r'^\s*def\s+vsp_run_file_allow_v5\s*\(\s*\)\s*:', ln):
        def_i=i
        break
if def_i is None:
    print("[ERR] cannot find: def vsp_run_file_allow_v5():")
    raise SystemExit(2)

def_indent=len(lines[def_i]) - len(lines[def_i].lstrip(" "))

# 2) locate end of function block
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

# 3) find LAST 'return jsonify(...)' or 'return flask.jsonify(...)' inside this function
ret_pat = re.compile(r'(?m)^(\s*)return\s+(?:flask\.)?jsonify\((.+)\)\s*$')
matches=list(ret_pat.finditer(block))
if not matches:
    # print quick hint lines
    hint="\n".join([ln.rstrip("\n") for ln in block.splitlines() if "return" in ln and "json" in ln][:30])
    print("[ERR] cannot find 'return jsonify(...)' in vsp_run_file_allow_v5()")
    print("[HINT] nearby return/json lines (first 30):\n"+hint)
    raise SystemExit(2)

m=matches[-1]
indent=m.group(1)
expr=m.group(2).strip()

# 4) build replacement block (wrap expr -> _rfa_resp)
rep = (
    f'{indent}# {MARK}\n'
    f'{indent}_rfa_resp = {expr}\n'
    f'{indent}try:\n'
    f'{indent}  if isinstance(_rfa_resp, dict):\n'
    f'{indent}    _f = _rfa_resp.get("findings")\n'
    f'{indent}    if not _f:\n'
    f'{indent}      _it = _rfa_resp.get("items")\n'
    f'{indent}      _dt = _rfa_resp.get("data")\n'
    f'{indent}      if isinstance(_it, list) and _it:\n'
    f'{indent}        _rfa_resp["findings"] = _it\n'
    f'{indent}      elif isinstance(_dt, list) and _dt:\n'
    f'{indent}        _rfa_resp["findings"] = _dt\n'
    f'{indent}except Exception:\n'
    f'{indent}  pass\n'
    f'{indent}return jsonify(_rfa_resp)\n'
)

new_block = block[:m.start()] + rep + block[m.end():]

out="".join(lines[:def_i]) + new_block + "".join(lines[end:])
p.write_text(out, encoding="utf-8")
print("[OK] patched:", MARK, "wrapped_expr=", expr[:80] + ("..." if len(expr)>80 else ""))
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
