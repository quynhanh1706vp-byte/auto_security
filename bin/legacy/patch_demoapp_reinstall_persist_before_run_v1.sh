#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_reinstall_persist_before_run_${TS}"
echo "[BACKUP] $F.bak_reinstall_persist_before_run_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_DEMOAPP_REINSTALL_PERSIST_UIREQ_BEFORE_RUN_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# tìm chỗ app.run( để chèn trước
m = re.search(r"(?m)^(?P<indent>\s*)app\.run\s*\(", txt)
if not m:
    # fallback: chèn cuối file
    insert_at = len(txt)
    indent = ""
else:
    insert_at = m.start()
    indent = m.group("indent")

block = f"""\n
{indent}# === {MARK} ===
{indent}try:
{indent}  # re-install persist wrapper at the very end (avoid being overwritten by watchdog hook)
{indent}  if '_vsp_demoapp_install_persist_uireq_on_status_v1' in globals():
{indent}    _vsp_demoapp_install_persist_uireq_on_status_v1(app)
{indent}    print('[{MARK}] re-installed persist wrapper on run_status_v1')
{indent}  else:
{indent}    print('[{MARK}] WARN: installer function not found (persist block missing?)')
{indent}except Exception as _e:
{indent}  print('[{MARK}] WARN:', _e)
{indent}# === END {MARK} ===\n
"""

txt2 = txt[:insert_at] + block + txt[insert_at:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK, "insert_at=", insert_at)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
