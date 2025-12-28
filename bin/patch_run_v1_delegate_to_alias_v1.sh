#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_delegate_${TS}"
echo "[BACKUP] $F.bak_runv1_delegate_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_DELEGATE_TO_ALIAS_V1 ==="
END = "# === END VSP_RUN_V1_DELEGATE_TO_ALIAS_V1 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# find decorator for /api/vsp/run_v1 (route/get/post)
dec = re.search(r"(?m)^@app\.(route|get|post)\(\s*['\"]/api/vsp/run_v1['\"][^\n]*\)\s*$", t)
if not dec:
    print("[WARN] cannot find decorator for /api/vsp/run_v1 -> skip (maybe already aliased)")
    raise SystemExit(0)

# find the def right after decorator
mdef = re.search(r"(?m)^def\s+([A-Za-z_]\w*)\s*\(\s*\)\s*:\s*$", t[dec.end():])
if not mdef:
    raise SystemExit("[ERR] cannot find def after /api/vsp/run_v1 decorator")

def_start = dec.end() + mdef.start()
def_end   = dec.end() + mdef.end()
fn_name = mdef.group(1)

# slice function body to next def
mnext = re.search(r"(?m)^def\s+\w+\s*\(", t[def_end:])
fn_end = (def_end + mnext.start()) if mnext else len(t)
seg = t[def_start:fn_end]

# detect function body indent
lines = seg.splitlines(True)
body_indent = None
for ln in lines[1:]:
    if ln.strip()=="":
        continue
    m = re.match(r"^([ \t]+)", ln)
    body_indent = m.group(1) if m else "    "
    break
if body_indent is None:
    body_indent = "    "

# insert after possible docstring (very small parser)
insert_at = 1  # after def line by default
if len(lines) > 1:
    l1 = lines[1]
    if re.match(rf"^{re.escape(body_indent)}(['\"]{{3}})", l1):
        q = re.match(rf"^{re.escape(body_indent)}(['\"]{{3}})", l1).group(1)
        # find closing triple quote
        j = 2
        while j < len(lines):
            if q in lines[j]:
                insert_at = j + 1
                break
            j += 1

block = (
    f"{body_indent}{TAG}\n"
    f"{body_indent}# Commercial: force /api/vsp/run_v1 to behave exactly like vsp_run_v1_alias (defaults + env_overrides)\n"
    f"{body_indent}return vsp_run_v1_alias()\n"
    f"{body_indent}{END}\n"
)

# if already delegating, skip
if "return vsp_run_v1_alias()" in seg:
    print("[OK] run_v1 already delegates to alias")
    raise SystemExit(0)

lines.insert(insert_at, block)
seg2 = "".join(lines)
t2 = t[:def_start] + seg2 + t[fn_end:]
p.write_text(t2, encoding="utf-8")
print(f"[OK] patched /api/vsp/run_v1 handler ({fn_name}) -> delegate to vsp_run_v1_alias()")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo
