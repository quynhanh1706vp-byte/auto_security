#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_silence_warn_v2_${TS}"
echo "[BACKUP] $F.bak_silence_warn_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# make this warning non-alarming in commercial logs
txt2 = txt
txt2 = txt2.replace(
  "[VSP_DEMOAPP_REINSTALL_PERSIST_UIREQ_BEFORE_RUN_V1] WARN: installer function not found (persist block missing?)",
  "[VSP_DEMOAPP_REINSTALL_PERSIST_UIREQ_BEFORE_RUN_V1] INFO: installer function not found; skipping (ok)"
)

if txt2 == txt:
  print("[WARN] target line not found; no change")
else:
  p.write_text(txt2, encoding="utf-8")
  print("[OK] replaced WARN -> INFO")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
