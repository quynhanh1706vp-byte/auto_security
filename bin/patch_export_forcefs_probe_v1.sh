#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_forcefs_probe_${TS}"
echo "[BACKUP] $F.bak_forcefs_probe_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "### [COMMERCIAL] FORCEFS_PROBE_V1 ###" in s:
    print("[OK] probe already exists")
    raise SystemExit(0)

m=re.search(r'(?m)^(\s*)def\s+api_vsp_run_export_v3_force_fs\s*\(.*\)\s*:\s*$', s)
if not m:
    raise SystemExit("[ERR] cannot find def api_vsp_run_export_v3_force_fs")

ind=m.group(1)
insert_at=m.end()

probe = f"""
{ind}    ### [COMMERCIAL] FORCEFS_PROBE_V1 ###
{ind}    if (request.args.get("probe") or "") == "1":
{ind}        resp = jsonify({{"ok": True, "probe": "FORCEFS_PROBE_V1"}})
{ind}        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
{ind}        resp.headers["X-VSP-EXPORT-MODE"] = "FORCEFS_PROBE_V1"
{ind}        return resp
"""

s = s[:insert_at] + probe + s[insert_at:]
p.write_text(s, encoding="utf-8")
print("[OK] inserted probe")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
