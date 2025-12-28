#!/usr/bin/env bash
set -euo pipefail

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

# Restore latest backup made by installer
LATEST="$(ls -1 "${APP}.bak_watchdog_hook_"* 2>/dev/null | sort | tail -n1 || true)"
[ -n "$LATEST" ] && [ -f "$LATEST" ] || { echo "[ERR] no ${APP}.bak_watchdog_hook_* found"; exit 1; }

cp -f "$LATEST" "$APP"
echo "[RESTORE] $APP <= $LATEST"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_fix_hook_indent_${TS}"
echo "[BACKUP] $APP.bak_fix_hook_indent_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

app_path = Path("vsp_demo_app.py")
lines = app_path.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# locate first "<appvar>.run("
run_i = None
appvar = None
indent = ""
for i, ln in enumerate(lines):
    m = re.match(r"^(\s*)(\w+)\.run\s*\(", ln)
    if m:
        run_i = i
        indent = m.group(1)
        appvar = m.group(2)
        break

if run_i is None or not appvar:
    raise SystemExit("[ERR] cannot find *.run( in vsp_demo_app.py")

# remove any previous injected hook block (if exists)
out = []
in_block = False
for ln in lines:
    if "VSP_WATCHDOG_HOOK_V1" in ln and "BEGIN" in ln:
        in_block = True
        continue
    if in_block:
        if "VSP_WATCHDOG_HOOK_V1" in ln and "END" in ln:
            in_block = False
        continue
    out.append(ln)
lines = out

# recompute run_i after removal
run_i = None
for i, ln in enumerate(lines):
    m = re.match(r"^(\s*)(\w+)\.run\s*\(", ln)
    if m:
        run_i = i
        indent = m.group(1)
        appvar = m.group(2)
        break

if run_i is None:
    raise SystemExit("[ERR] cannot re-find *.run( after cleanup")

unit = "\t" if "\t" in indent else "    "
inner = indent + unit

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
app_path.write_text("".join(lines), encoding="utf-8")

print(f"[OK] injected indent-aware hook before {appvar}.run(...) at line {run_i+1}")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py OK"
echo "[DONE] hook indent fixed"
