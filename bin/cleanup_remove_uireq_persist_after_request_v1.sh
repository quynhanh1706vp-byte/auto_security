#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_rm_afterreq_${TS}"
echo "[BACKUP] $F.bak_rm_afterreq_${TS}"

python3 - <<'PY'
import re
from pathlib import Path
p=Path("vsp_demo_app.py")
t=p.read_text(encoding="utf-8", errors="ignore")
pat=r"\n# === VSP_UIREQ_PERSIST_AFTER_REQUEST_V1 ===[\s\S]*?# === END VSP_UIREQ_PERSIST_AFTER_REQUEST_V1 ===\n"
t2,repl=re.subn(pat,"\n",t,flags=re.M)
print("[OK] removed blocks =",repl)
p.write_text(t2,encoding="utf-8")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
