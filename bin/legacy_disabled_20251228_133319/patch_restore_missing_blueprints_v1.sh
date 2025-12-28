#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="./vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_restore_bp_${TS}"
echo "[BACKUP] $F.bak_restore_bp_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG_BP  = "VSP_RESTORE_MISSING_BLUEPRINTS_V1"
TAG_REG = "VSP_REGISTER_RESTORED_BLUEPRINTS_V1"

# 1) find blueprint-like vars used in decorators: @xxx.get( / @xxx.post( / @xxx.route(
decor_pat = re.compile(r'(?m)^\s*@\s*([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(get|post|put|delete|route)\s*\(')
bps = sorted({m.group(1) for m in decor_pat.finditer(t) if m.group(1).endswith("_bp")})
print("[INFO] decorator bp vars:", bps)

# 2) find which are missing definition "<bp> = Blueprint("
missing = []
for bp in bps:
    if not re.search(rf'(?m)^\s*{re.escape(bp)}\s*=\s*Blueprint\s*\(', t):
        missing.append(bp)
print("[INFO] missing bp defs:", missing)

def insert_after_imports(txt, payload):
    m = re.search(r"(?ms)\A(.*?\n)(\s*(?:from|import)\s+[^\n]+\n(?:\s*(?:from|import)\s+[^\n]+\n)*)", txt)
    pos = m.end(0) if m else 0
    return txt[:pos] + payload + txt[pos:]

changed = False

# 3) insert bp definitions (only if missing and tag not present)
if missing and TAG_BP not in t:
    defs = "\n".join([f'{bp} = _VSP_Blueprint("{bp}", __name__)' for bp in missing])
    payload = f"""
# === {TAG_BP} ===
try:
    from flask import Blueprint as _VSP_Blueprint
except Exception:
    _VSP_Blueprint = None

if _VSP_Blueprint is not None:
    {defs}
# === END {TAG_BP} ===

"""
    t = insert_after_imports(t, payload)
    changed = True

# 4) register into app after "app = Flask(...)" (only if not already registered tag)
if (missing and TAG_REG not in t):
    mapp = re.search(r'(?m)^\s*app\s*=\s*Flask\s*\(.*\)\s*$', t)
    reg_block = f"""
# === {TAG_REG} ===
try:
    _bps = [{", ".join([f'"{bp}"' for bp in missing])}]
    for _n in _bps:
        _bp = globals().get(_n, None)
        if _bp is None:
            continue
        # avoid double register
        try:
            _have = getattr(app, "blueprints", {{}})
            if _bp.name in _have:
                continue
        except Exception:
            pass
        try:
            app.register_blueprint(_bp)
        except Exception:
            pass
except Exception:
    pass
# === END {TAG_REG} ===

"""
    if mapp:
        pos = mapp.end()
        t = t[:pos] + reg_block + t[pos:]
        changed = True
    else:
        # fallback: append near end
        t = t.rstrip() + "\n\n" + reg_block + "\n"
        changed = True

if changed:
    p.write_text(t, encoding="utf-8")
    print("[OK] patched:", p)
else:
    print("[OK] no changes needed")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] restore blueprints patch applied"
