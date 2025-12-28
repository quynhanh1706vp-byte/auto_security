#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="./vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_canon_uireq_${TS}"
echo "[BACKUP] $F.bak_canon_uireq_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

changed = False

# 1) raw string replacements
rep = {
  "ui/ui/out_ci/uireq_v1": "ui/out_ci/uireq_v1",
  "/ui/ui/out_ci/uireq_v1": "/ui/out_ci/uireq_v1",
  "out_ci/ui_req_state": "out_ci/uireq_v1",
  "out_ci/ui_req_state/": "out_ci/uireq_v1/",
}
for a,b in rep.items():
    if a in t:
        t = t.replace(a,b); changed = True

TAG = "VSP_UIREQ_CANON_DIR_V1"
canon = 'UIREQ_STATE_DIR = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1")  # ' + TAG

if TAG not in t:
    # insert near top after minimal imports tag if present, else after first 80 lines
    m = re.search(r"(?ms)^# === VSP_MIN_IMPORTS_COMMERCIAL_V1 ===.*?# === END VSP_MIN_IMPORTS_COMMERCIAL_V1 ===\s*\n", t)
    if m:
        pos = m.end()
        t = t[:pos] + canon + "\n" + t[pos:]
        changed = True
    else:
        # fallback: insert after first imports block
        m2 = re.search(r"(?ms)\A.*?(?:\n\n|\Z)", t)
        pos = m2.end() if m2 else 0
        t = t[:pos] + canon + "\n" + t[pos:]
        changed = True

# 2) best-effort: rewrite any Path(".../uireq...") to use UIREQ_STATE_DIR when easy
# (only simple literal occurrences)
t2 = re.sub(r'Path\(\s*["\'](/home/test/Data/SECURITY_BUNDLE/ui/)?out_ci/(ui_req_state|uireq_v1)["\']\s*\)',
            'UIREQ_STATE_DIR', t)
if t2 != t:
    t = t2; changed = True

if changed:
    p.write_text(t, encoding="utf-8")
    print("[OK] canonical uireq path patched")
else:
    print("[OK] no changes needed")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] uireq path canonicalized"
