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
cp -f "$WSGI" "${WSGI}.bak_rfallow_findingsfb_v4_${TS}"
echo "[BACKUP] ${WSGI}.bak_rfallow_findingsfb_v4_${TS}"

python3 - "$WSGI" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_RUN_FILE_ALLOW_FINDINGS_FALLBACK_V4"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) locate decorator line for run_file_allow
lines=s.splitlines(True)
idx=None
for i,ln in enumerate(lines):
    if "run_file_allow" in ln and ln.lstrip().startswith("@"):
        idx=i
        break
if idx is None:
    # fallback: search by function name
    for i,ln in enumerate(lines):
        if re.search(r'^\s*def\s+\w*run_file_allow\w*\s*\(', ln):
            idx=i
            break
if idx is None:
    print("[ERR] cannot locate run_file_allow decorator/def")
    raise SystemExit(2)

# 2) find def line
def_i=None
for j in range(idx, min(idx+80, len(lines))):
    if re.match(r'^\s*def\s+\w+\s*\(', lines[j]):
        def_i=j
        break
if def_i is None:
    print("[ERR] cannot locate def after run_file_allow decorator")
    raise SystemExit(2)

def_indent=len(lines[def_i]) - len(lines[def_i].lstrip(" "))
# 3) find end of function block (next top-level def with same indent, or EOF)
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

# 4) discover JSON object var used inside the handler
obj_var=None

# prefer json.load assignment
m=re.search(r'(?m)^\s*(\w+)\s*=\s*json\.load\s*\(', block)
if m: obj_var=m.group(1)

# else: json.loads assignment
if not obj_var:
    m=re.search(r'(?m)^\s*(\w+)\s*=\s*json\.loads\s*\(', block)
    if m: obj_var=m.group(1)

# else: first ".get('findings')" receiver
if not obj_var:
    m=re.search(r'(\w+)\.get\(\s*([\'"])findings\2\s*\)', block)
    if m: obj_var=m.group(1)

if not obj_var:
    print("[ERR] cannot infer JSON object var in run_file_allow block")
    raise SystemExit(2)

# 5) patch: in THIS function block only, replace var.get("findings") with fallback
# (protect against double-wrapping)
pat = re.compile(rf'(?<!or\s){re.escape(obj_var)}\.get\(\s*([\'"])findings\1\s*\)')
def repl(m):
    q=m.group(1)
    orig=f'{obj_var}.get({q}findings{q})'
    return f'({orig} or {obj_var}.get({q}items{q}) or {obj_var}.get({q}data{q}))'

new_block, n = pat.subn(repl, block)
if n == 0:
    # maybe findings extracted into variable; patch that assignment if possible
    # e.g., findings = obj.get("findings")
    pat2 = re.compile(rf'(?m)^(\s*findings\s*=\s*){re.escape(obj_var)}\.get\(\s*([\'"])findings\2\s*\)\s*$')
    def repl2(m):
        pre=m.group(1); q=m.group(2)
        return pre + f'({obj_var}.get({q}findings{q}) or {obj_var}.get({q}items{q}) or {obj_var}.get({q}data{q}) or [])'
    new_block, n = pat2.subn(repl2, block)

if n == 0:
    print("[ERR] no '.get(findings)' occurrence to patch inside run_file_allow block")
    raise SystemExit(2)

# 6) insert marker comment near top of function (right after def line)
blk_lines=new_block.splitlines(True)
blk_lines.insert(1, f'{" "*(def_indent+2)}# {MARK}\n')
new_block="".join(blk_lines)

# 7) write back
out="".join(lines[:def_i]) + new_block + "".join(lines[end:])
p.write_text(out, encoding="utf-8")
print("[OK] patched run_file_allow findings fallback; obj_var=", obj_var, "replacements=", n)
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"

echo "== verify =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=3" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"findings_len=",len(j.get("findings") or []),"items_len=",len(j.get("items") or []),"data_len=",len(j.get("data") or []),"from=",j.get("from"))'
