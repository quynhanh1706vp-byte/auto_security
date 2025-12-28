#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="api/vsp_run_export_api_v3.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_ondemand_harden_${TS}"
echo "[BACKUP] $F.bak_export_ondemand_harden_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("api/vsp_run_export_api_v3.py")
s=p.read_text(encoding="utf-8", errors="replace")

# (A) Ensure deps imports exist somewhere (safe even if duplicates)
inject_marker = "# [COMMERCIAL] EXPORT_ONDEMAND_DEPS_V1"
if inject_marker not in s:
    deps = "\n" + inject_marker + "\n" + \
           "import os, json\n" + \
           "import glob, shutil, tempfile, subprocess, zipfile\n"
    # insert after first import/from block
    m = re.search(r'(?m)^(import .+|from .+ import .+)\n', s)
    if m:
        # insert after the first block of contiguous import/from lines
        m2 = re.search(r'(?ms)^((?:import .+\n|from .+ import .+\n)+)', s)
        if m2:
            s = s[:m2.end()] + deps + s[m2.end():]
        else:
            s = deps + s
    else:
        s = deps + s

# (B) Replace the "except Exception: pass" of on-demand block so it DOES NOT fall back to pdf_not_enabled
# We patch ONLY the block that contains the comment "# [COMMERCIAL] on-demand export"
pat = r'(?s)(# \[COMMERCIAL\] on-demand export.*?try:.*?)(except Exception:\s*\n\s*pass)'
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find on-demand block to harden (missing marker '# [COMMERCIAL] on-demand export')")

replacement = m.group(1) + (
    "except Exception as e:\n"
    "        # do not silently fallback to stub (pdf_not_enabled)\n"
    "        resp = jsonify({\"ok\": False, \"error\": \"export_ondemand_exception\", "
    "\"detail\": f\"{type(e).__name__}:{e}\"})\n"
    "        resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"0\"\n"
    "        resp.headers[\"X-VSP-EXPORT-MODE\"] = \"ONDEMAND_V2_EXCEPTION\"\n"
    "        return resp, 500\n"
)

s = s[:m.start()] + replacement + s[m.end():]
p.write_text(s, encoding="utf-8")
print("[OK] hardened on-demand block + ensured imports")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"
