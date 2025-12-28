#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_alias_min_${TS}"
echo "[BACKUP] $F.bak_runv1_alias_min_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
t=p.read_text(encoding="utf-8", errors="ignore")

TAG="# === VSP_RUN_V1_ALIAS_ACCEPT_MINIMAL_V2 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

m = re.search(r"^def\s+vsp_run_v1_alias\s*\(\s*\)\s*:\s*$", t, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def vsp_run_v1_alias()")

start = m.end()
mnext = re.search(r"^def\s+[A-Za-z0-9_]+\s*\(", t[start:], flags=re.M)
end = start + (mnext.start() if mnext else len(t[start:]))

block = t[m.start():end]
if TAG in block:
    print("[OK] already patched in block"); raise SystemExit(0)

lines = block.splitlines(True)

# insert right after def line
out=[]
inserted=False
for i,ln in enumerate(lines):
    out.append(ln)
    if (not inserted) and ln.startswith("def vsp_run_v1_alias"):
        # next line should be indentation; inject after it
        pass
    if (not inserted) and re.match(r"^def\s+vsp_run_v1_alias", ln):
        continue
    if (not inserted) and re.match(r"^\s{4}\S", ln):
        # first indented line => insert before it
        indent=" " * 4
        inj = (
            f"{indent}{TAG}\n"
            f"{indent}# commercial: accept minimal JSON (fill defaults)\n"
            f"{indent}try:\n"
            f"{indent}    payload = request.get_json(silent=True) or {{}}\n"
            f"{indent}    if not isinstance(payload, dict): payload = {{}}\n"
            f"{indent}    payload.setdefault('mode','local')\n"
            f"{indent}    payload.setdefault('profile','FULL_EXT')\n"
            f"{indent}    payload.setdefault('target_type','path')\n"
            f"{indent}    payload.setdefault('target','/home/test/Data/SECURITY-10-10-v4')\n"
            f"{indent}    request._cached_json = (payload, payload)\n"
            f"{indent}except Exception:\n"
            f"{indent}    pass\n"
            f"{indent}# === END VSP_RUN_V1_ALIAS_ACCEPT_MINIMAL_V2 ===\n"
        )
        out.insert(len(out)-1, inj)
        inserted=True

new_block="".join(out)
t2 = t[:m.start()] + new_block + t[end:]
p.write_text(t2, encoding="utf-8")
print("[OK] patched vsp_run_v1_alias minimal defaults")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== smoke POST run_v1 with empty payload (should not 400) =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" -H "Content-Type: application/json" -d '{}' | sed -n '1,40p'
