#!/usr/bin/env bash
set -euo pipefail
H="run_api/vsp_watchdog_hook_v1.py"
[ -f "$H" ] || { echo "[ERR] missing $H"; exit 1; }

cp -f "$H" "$H.bak_respfix_$(date +%Y%m%d_%H%M%S)"
echo "[BACKUP] $H.bak_respfix_*"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_watchdog_hook_v1.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# Replace the "data =" extraction block inside wrapped_run with a robust one
# We look for the first occurrence of "try:\n            data =" style and patch conservatively.
pat = re.compile(r"""
        try:\n
            data\s*=\s*resp\.get_json\(silent=True\)\s*if\s*hasattr\(resp,\s*"get_json"\)\s*else\s*None\n
        except\s+Exception:\n
            data\s*=\s*None\n
""", re.VERBOSE)

rep = r"""
        # Robustly extract json/dict from Flask return types: Response | (Response, code) | dict
        data = None
        base = resp[0] if isinstance(resp, tuple) and len(resp) > 0 else resp
        try:
            if isinstance(base, dict):
                data = base
            elif hasattr(base, "get_json"):
                data = base.get_json(silent=True)
        except Exception:
            data = None
"""

if not pat.search(s):
    # fallback: inject helper function and use it
    if "_vsp_extract_json_v1" not in s:
        s = s.replace("def install(app):", """
def _vsp_extract_json_v1(resp):
    base = resp[0] if isinstance(resp, tuple) and len(resp) > 0 else resp
    try:
        if isinstance(base, dict):
            return base
        if hasattr(base, "get_json"):
            return base.get_json(silent=True)
    except Exception:
        return None
    return None

def install(app):
""")
    s = re.sub(r"data\s*=\s*None\s*\n", "data = _vsp_extract_json_v1(resp)\n", s, count=1)
else:
    s = pat.sub(rep, s, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] patched hook response parsing")
PY

python3 -m py_compile run_api/vsp_watchdog_hook_v1.py
echo "[OK] py_compile hook OK"
