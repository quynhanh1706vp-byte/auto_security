#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="./vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_uireq_selfref_${TS}"
echo "[BACKUP] $F.bak_fix_uireq_selfref_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# Replace the bad line (exactly that self-ref) with correct canonical definition.
bad_pat = r'(?m)^\s*UIREQ_STATE_DIR\s*=\s*UIREQ_STATE_DIR\s*#\s*VSP_UIREQ_CANON_DIR_V1\s*$'
good = 'UIREQ_STATE_DIR = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1")  # VSP_UIREQ_CANON_DIR_V1'

if re.search(bad_pat, t):
    t = re.sub(bad_pat, good, t, count=1)
    p.write_text(t, encoding="utf-8")
    print("[OK] fixed UIREQ_STATE_DIR self-reference")
else:
    # fallback: if tag exists but wrong form, force-set any tagged assignment
    pat2 = r'(?m)^\s*UIREQ_STATE_DIR\s*=.*#\s*VSP_UIREQ_CANON_DIR_V1\s*$'
    if re.search(pat2, t):
        t = re.sub(pat2, good, t, count=1)
        p.write_text(t, encoding="utf-8")
        print("[OK] forced UIREQ_STATE_DIR canonical assignment")
    else:
        print("[INFO] no tagged UIREQ_STATE_DIR line found; no change")

PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] fix applied"
