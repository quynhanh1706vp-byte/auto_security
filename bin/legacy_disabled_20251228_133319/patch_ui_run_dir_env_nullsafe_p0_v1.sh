#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_run_dir_nullsafe_${TS}"
echo "[BACKUP] $F.bak_run_dir_nullsafe_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

before=s
s=s.replace('os.environ["RUN_DIR"]', 'os.environ.get("RUN_DIR","")')
s=s.replace("os.environ['RUN_DIR']", 'os.environ.get("RUN_DIR","")')

if s==before:
    print("[OK] no RUN_DIR env direct access found (skip)")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched RUN_DIR env access to nullsafe get()")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

# restart UI
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
