#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="api/vsp_run_export_api_v3.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_bp_${TS}"
echo "[BACKUP] $F.bak_fix_bp_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("api/vsp_run_export_api_v3.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Remove the bad override block that starts with marker and contains "@bp.route(...run_export_v3...)"
# We only remove the override section, not your main exporter.
patterns = [
    r"### \[COMMERCIAL\] EXPORT_V3_OVERRIDE_V3 ###.*",  # if exists
]
changed=False

# 1) If the file contains any decorator "@bp.route(" -> replace "@bp." with "@bp_run_export_v3."
# This is safer than deleting if you want to keep the override.
if "@bp.route(\"/api/vsp/run_export_v3/<rid>\")" in s or "@bp.route('/api/vsp/run_export_v3/<rid>')" in s:
    s = s.replace("@bp.route(\"/api/vsp/run_export_v3/<rid>\")",
                  "@bp_run_export_v3.route(\"/api/vsp/run_export_v3/<rid>\")")
    s = s.replace("@bp.route('/api/vsp/run_export_v3/<rid>')",
                  "@bp_run_export_v3.route('/api/vsp/run_export_v3/<rid>')")
    changed=True

# 2) Also fix any remaining '@bp.route(' occurrences to bp_run_export_v3 to avoid future NameError
if "@bp.route(" in s:
    s = s.replace("@bp.route(", "@bp_run_export_v3.route(")
    changed=True

p.write_text(s, encoding="utf-8")
print("[OK] patched decorator bp -> bp_run_export_v3, changed=", changed)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
