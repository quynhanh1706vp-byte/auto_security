#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_findfallback_${TS}"
echo "[BACKUP] $F.bak_findfallback_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")
if "VSP_FINDINGS_FALLBACK_CANDIDATES_V1" in s:
    print("[OK] already patched, skip")
    raise SystemExit(0)

# Find a place to insert helpers (after imports is fine)
ins_pos = 0
m = re.search(r'^\s*from flask import .*$', s, re.M)
if m:
    ins_pos = s.find("\n", m.end())
    if ins_pos < 0: ins_pos = m.end()

helper = r'''
# === VSP_FINDINGS_FALLBACK_CANDIDATES_V1 ===
import os as _os
def _vsp_pick_findings_file(run_dir: str):
    cands = [
        "findings_unified_current.json",
        "findings_unified_commercial_v2.json",
        "findings_unified_commercial.json",
        "findings_unified.json",
        "findings_unified_commercial_v2.sarif",
        "findings_unified.sarif",
    ]
    for name in cands:
        fp = _os.path.join(run_dir, name)
        if _os.path.isfile(fp) and _os.path.getsize(fp) > 0:
            return fp
    return None
# === /VSP_FINDINGS_FALLBACK_CANDIDATES_V1 ===
'''

s = s[:ins_pos+1] + helper + s[ins_pos+1:]

# Patch common patterns: "findings_unified_current.json" hardcoded
s2 = s.replace('findings_unified_current.json', 'findings_unified_current.json')  # no-op, keep readable

# Heuristic: wherever code does something like fp=os.path.join(run_dir,"findings_unified_current.json")
# we inject: fp=_vsp_pick_findings_file(run_dir) or the original.
s2 = re.sub(
    r'(fp\s*=\s*os\.path\.join\(\s*run_dir\s*,\s*[\'"]findings_unified_current\.json[\'"]\s*\))',
    r'fp = _vsp_pick_findings_file(run_dir) or os.path.join(run_dir, "findings_unified_current.json")',
    s2
)

# Also common: file_name="findings_unified_current.json"
s2 = re.sub(
    r'([\'"]findings_unified_current\.json[\'"])',
    r'\1', s2
)

p.write_text(s2, encoding="utf-8")
print("[OK] patched findings fallback helper + fp selection")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 gunicorn"
