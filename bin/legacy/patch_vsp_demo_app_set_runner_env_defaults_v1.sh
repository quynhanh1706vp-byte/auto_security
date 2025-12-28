#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_env_defaults_${TS}"
echo "[BACKUP] $F.bak_env_defaults_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_COMMERCIAL_ENV_DEFAULTS_V1"
if MARK in txt:
    print("[OK] already patched")
    raise SystemExit(0)

# Insert after first import os (or at top)
insert = """
# === VSP_COMMERCIAL_ENV_DEFAULTS_V1 ===
import os as _os
_os.environ.setdefault("VSP_BUNDLE_ROOT", "/home/test/Data/SECURITY_BUNDLE")
_os.environ.setdefault("VSP_RUNNER", "/home/test/Data/SECURITY_BUNDLE/bin/run_all_tools_v2.sh")
# timeouts (UI watchdog)
_os.environ.setdefault("VSP_UIREQ_STALL_TIMEOUT_SEC", "600")
_os.environ.setdefault("VSP_UIREQ_TOTAL_TIMEOUT_SEC", "7200")
# === END VSP_COMMERCIAL_ENV_DEFAULTS_V1 ===

"""

m = re.search(r"(?m)^\s*import\s+os\s*$", txt)
if m:
    pos = m.end()
    txt = txt[:pos] + "\n" + insert + txt[pos:]
else:
    txt = insert + txt

p.write_text(txt, encoding="utf-8")
print("[OK] inserted env defaults into", p)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
echo "[DONE]"
