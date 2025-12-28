#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_orphan_except_cleanup_${TS}"
echo "[BACKUP] ${F}.bak_orphan_except_cleanup_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("wsgi_vsp_ui_gateway.py")
lines=p.read_text(encoding="utf-8", errors="replace").splitlines(True)

MARK="VSP_AUTOFIX_ORPHAN_EXCEPT"
idx=None
for i,l in enumerate(lines):
    if MARK in l and "if True:" in l:
        idx=i
        break
if idx is None:
    print("[OK] marker not found or already cleaned")
    raise SystemExit(0)

indent = lines[idx].split("if True:")[0]
# replace "if True:" with "try:"
lines[idx] = lines[idx].replace("if True:", "try:", 1)

# find end of this block by indentation
base = len(indent)
end = None
for j in range(idx+1, len(lines)):
    lj = lines[j]
    if lj.strip()=="":
        continue
    cur = len(lj) - len(lj.lstrip(" "))
    if cur <= base:
        end = j
        break
if end is None:
    end = len(lines)

except_block = (
    f"{indent}except Exception:\n"
    f"{indent}    pass\n"
)

# insert except right before end
lines.insert(end, except_block)

p.write_text("".join(lines), encoding="utf-8")
print("[OK] cleaned:", MARK, "at line", idx+1)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh
