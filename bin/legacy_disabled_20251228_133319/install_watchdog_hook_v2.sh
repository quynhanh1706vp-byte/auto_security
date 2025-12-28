#!/usr/bin/env bash
set -euo pipefail

APP="vsp_demo_app.py"
HOOK="run_api/vsp_watchdog_hook_v1.py"
WD="run_api/vsp_watchdog_v1.py"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
[ -f "$HOOK" ] || { echo "[ERR] missing $HOOK"; exit 1; }
[ -f "$WD" ] || { echo "[ERR] missing $WD"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_watchdog_hook_v2_${TS}"
echo "[BACKUP] $APP.bak_watchdog_hook_v2_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# 1) remove any previous hook block (clean)
out=[]
skip=False
for ln in lines:
    if "BEGIN VSP_WATCHDOG_HOOK_V1" in ln:
        skip=True
        continue
    if skip:
        if "END VSP_WATCHDOG_HOOK_V1" in ln:
            skip=False
        continue
    # also remove stray lines from older injections
    if "run_api.vsp_watchdog_hook_v1" in ln or "VSP_WD_HOOK" in ln:
        continue
    out.append(ln)
lines = out

# 2) find first "<appvar>.run("
run_i=None
appvar=None
indent=""
for i, ln in enumerate(lines):
    m = re.match(r"^(\s*)(\w+)\.run\s*\(", ln)
    if m:
        run_i=i
        indent=m.group(1)
        appvar=m.group(2)
        break
if run_i is None:
    raise SystemExit("[ERR] cannot find *.run( in vsp_demo_app.py")

# 3) detect indent unit near run_i (min positive diff between indent lengths)
def indlen(s): return len(s.expandtabs(8))
lens=set()
for j in range(max(0, run_i-200), min(len(lines), run_i+50)):
    ln=lines[j]
    if ln.strip()=="":
        continue
    ws=re.match(r"^(\s*)", ln).group(1)
    lens.add(indlen(ws))
lens=sorted(lens)
unit=2
for a,b in zip(lens, lens[1:]):
    d=b-a
    if d>0:
        unit=d
        break
# If indent uses tabs, keep tab unit
if "\t" in indent:
    inner = indent + "\t"
else:
    inner = indent + (" " * unit)

hook = [
    "\n",
    f"{indent}# === BEGIN VSP_WATCHDOG_HOOK_V1 ===\n",
    f"{indent}try:\n",
    f"{inner}from run_api.vsp_watchdog_hook_v1 import install as _vsp_wd_install\n",
    f"{inner}_vsp_wd_install({appvar})\n",
    f"{indent}except Exception as _e:\n",
    f"{inner}print('[VSP_WD_HOOK] install failed:', _e)\n",
    f"{indent}# === END VSP_WATCHDOG_HOOK_V1 ===\n",
    "\n",
]

lines[run_i:run_i] = hook
p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] injected hook before {appvar}.run(...) at line {run_i+1} (unit={unit})")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py OK"
