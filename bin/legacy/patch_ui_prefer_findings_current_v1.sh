#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

if grep -q "VSP_FINDINGS_RESOLVE_V1" "$F"; then
  echo "[OK] already patched: $F"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_findings_resolve_${TS}"
echo "[BACKUP] $F.bak_findings_resolve_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

helper = r'''
# ---- commercial findings resolver ----  # VSP_FINDINGS_RESOLVE_V1
def vsp_resolve_findings_file(run_dir: str):
    import os
    cands = [
        "findings_unified_current.json",
        "findings_unified_commercial_v2.json",
        "findings_unified_commercial.json",
        "findings_unified.json",
    ]
    for name in cands:
        fp = os.path.join(run_dir, name)
        if os.path.isfile(fp) and os.path.getsize(fp) > 0:
            return fp
    return None
# ---- end resolver ----
'''

# insert helper after imports (after first blank line following imports)
if "VSP_FINDINGS_RESOLVE_V1" not in s:
    m = re.search(r'(^import .+\n|^from .+ import .+\n)+', s, flags=re.M)
    if m:
        ins = m.end()
        s = s[:ins] + "\n" + helper + s[ins:]
    else:
        s = helper + "\n" + s

# replace common hardcoded filenames in join(...) calls inside endpoints
# 1) os.path.join(run_dir, "findings_unified_commercial.json") -> vsp_resolve_findings_file(run_dir) or fallback
repls = [
    r'os\.path\.join\(\s*run_dir\s*,\s*["\']findings_unified_commercial_v2\.json["\']\s*\)',
    r'os\.path\.join\(\s*run_dir\s*,\s*["\']findings_unified_commercial\.json["\']\s*\)',
    r'os\.path\.join\(\s*run_dir\s*,\s*["\']findings_unified\.json["\']\s*\)',
]
for rx in repls:
    s = re.sub(rx, r'(vsp_resolve_findings_file(run_dir) or os.path.join(run_dir,"findings_unified_commercial.json"))', s)

p.write_text(s, encoding="utf-8")
print("[OK] patched vsp_demo_app.py (resolver + replacements)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[DONE] patched $F (restart 8910 to take effect)"
