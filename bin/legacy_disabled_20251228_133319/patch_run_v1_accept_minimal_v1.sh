#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_min_${TS}"
echo "[BACKUP] $F.bak_runv1_min_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
t=p.read_text(encoding="utf-8", errors="ignore")

TAG="# === VSP_RUN_V1_ACCEPT_MINIMAL_V1 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# find run_v1 handler by decorator /api/vsp/run_v1
m = re.search(r"^@app\.(route|post)\(\s*['\"]/api/vsp/run_v1['\"][^\)]*\)\s*$", t, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find /api/vsp/run_v1 decorator")

off=m.end()
mdef=re.search(r"^def\s+([A-Za-z0-9_]+)\s*\(", t[off:], flags=re.M)
if not mdef:
    raise SystemExit("[ERR] cannot find handler def after decorator")
fn=mdef.group(1)
def_start=off+mdef.start()
# end at next top-level def
mnext=re.search(r"^def\s+[A-Za-z0-9_]+\s*\(", t[off+mdef.end():], flags=re.M)
end=(off+mdef.end()+mnext.start()) if mnext else len(t)
block=t[def_start:end]

# inject fallback right after function signature line (first line of block)
lines=block.splitlines(True)
# find first non-empty line after def ...:
ins_i=1
indent=" " * 4
fallback = (
    f"{indent}{TAG}\n"
    f"{indent}# commercial: accept minimal/empty JSON; fill defaults\n"
    f"{indent}try:\n"
    f"{indent}    payload = request.get_json(silent=True) or {{}}\n"
    f"{indent}    if not isinstance(payload, dict): payload = {{}}\n"
    f"{indent}    payload.setdefault('mode','local')\n"
    f"{indent}    payload.setdefault('profile','FULL_EXT')\n"
    f"{indent}    payload.setdefault('target_type','path')\n"
    f"{indent}    payload.setdefault('target','/home/test/Data/SECURITY-10-10-v4')\n"
    f"{indent}    # expose back to existing logic if it reads request.json\n"
    f"{indent}    request._cached_json = (payload, payload)\n"
    f"{indent}except Exception:\n"
    f"{indent}    pass\n"
    f"{indent}# === END VSP_RUN_V1_ACCEPT_MINIMAL_V1 ===\n"
)
lines.insert(ins_i, fallback)
new_block="".join(lines)
t2=t[:def_start]+new_block+t[end:]
p.write_text(t2, encoding="utf-8")
print("[OK] patched run_v1 handler:", fn)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== smoke POST run_v1 (empty payload) =="
curl -sS -X POST "http://127.0.0.1:8910/api/vsp/run_v1" -H "Content-Type: application/json" -d '{}' | head
echo
