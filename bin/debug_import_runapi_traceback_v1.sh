#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
python3 - <<'PY'
import traceback
try:
    import run_api.vsp_run_api_v1 as m
    print("[OK] imported run_api.vsp_run_api_v1")
    print("has bp_vsp_run_api_v1:", hasattr(m, "bp_vsp_run_api_v1"))
    print("bp_vsp_run_api_v1 =", getattr(m, "bp_vsp_run_api_v1", None))
except Exception as e:
    print("[ERR] import failed:", repr(e))
    traceback.print_exc()
PY
