#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

python3 - "$APP" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
A="# --- VSP_P0_API_RUN_FILES_V1_WHITELIST ---"
B="# --- /VSP_P0_API_RUN_FILES_V1_WHITELIST ---"

if A not in s or B not in s:
    print("[OK] run_files_v1 marker NOT present in vsp_demo_app.py (nothing to move). This is expected if you already rolled back.")
    raise SystemExit(0)

print("[INFO] marker exists -> use the original move script if you really need it.")
PY
