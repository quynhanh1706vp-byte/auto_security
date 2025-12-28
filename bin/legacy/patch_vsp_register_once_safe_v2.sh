#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_regonce_v2_${TS}"
echo "[BACKUP] $F.bak_regonce_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
txt=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_REGISTER_RUNAPI_ONCE_V2" in txt:
    print("[SKIP] already patched")
    raise SystemExit(0)

needle = "OK registered: /api/vsp/run_v1"
pos = txt.find(needle)
if pos == -1:
    raise SystemExit("[ERR] cannot find needle: " + needle)

# find the nearest preceding "def <name>(" before pos
defs = list(re.finditer(r"^def\s+([A-Za-z_]\w*)\s*\(", txt, flags=re.M))
cand = None
for m in defs:
    if m.start() < pos:
        cand = m
    else:
        break
if not cand:
    raise SystemExit("[ERR] no preceding def found before needle; cannot patch safely")

fname = cand.group(1)
start = cand.start()

# get function block end: next def at column 0
after = txt[cand.end():]
m2 = re.search(r"^def\s+\w+\s*\(", after, flags=re.M)
end = cand.end() + (m2.start() if m2 else len(after))

func = txt[start:end]
lines = func.splitlines(True)

# find indent used in function body (first non-empty line after def)
body_indent = "  "
for ln in lines[1:]:
    if ln.strip():
        body_indent = ln[:len(ln)-len(ln.lstrip())]
        break

# inject guard right after def line
out = []
out.append(lines[0])
guard = (
    f"{body_indent}# === VSP_REGISTER_RUNAPI_ONCE_V2 ===\n"
    f"{body_indent}g = globals()\n"
    f"{body_indent}if g.get('VSP_RUN_API_REGISTERED_ONCE'):\n"
    f"{body_indent}  return\n"
    f"{body_indent}g['VSP_RUN_API_REGISTERED_ONCE'] = True\n"
    f"{body_indent}# === END VSP_REGISTER_RUNAPI_ONCE_V2 ===\n"
)
out.append(guard)
out.extend(lines[1:])

func2 = "".join(out)
txt2 = txt[:start] + func2 + txt[end:]
p.write_text(txt2, encoding="utf-8")
print(f"[OK] wrapped function '{fname}' with register-once guard")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== grep VSP_RUN_API (should show OK registered once) =="
grep -n "VSP_RUN_API" out_ci/ui_8910.log | head -n 30 || true
