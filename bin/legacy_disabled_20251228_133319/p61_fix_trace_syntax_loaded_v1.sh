#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
files=(
  "static/js/vsp_bundle_tabs5_v1.js"
  "static/js/vsp_dashboard_luxe_v1.js"
)

python3 - <<'PY'
import re, datetime
from pathlib import Path

TS=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
files=[
  Path("static/js/vsp_bundle_tabs5_v1.js"),
  Path("static/js/vsp_dashboard_luxe_v1.js"),
]

def patch_text(s:str)->tuple[str,int]:
  n=0
  # case: ..., "TRACE"}  => ..., trace:"TRACE"}
  s2, c = re.subn(r',\s*"TRACE"\s*}', r', trace:"TRACE"}', s); n+=c; s=s2

  # case: ..., INFO:2, 1 } => ..., INFO:2, TRACE:1 }
  s2, c = re.subn(r'(\bINFO\s*:\s*\d+\s*),\s*(\d+)\s*}', r'\1, TRACE:\2}', s); n+=c; s=s2

  # case: ..., CRITICAL:0,...,INFO:0, 0 } => add TRACE:0 (keyless number at end)
  s2, c = re.subn(r'(\bCRITICAL\s*:\s*\d+[^{}]*\bINFO\s*:\s*\d+\s*),\s*(\d+)\s*}', r'\1, TRACE:\2}', s); n+=c; s=s2

  # case: {...,INFO:4,5}; (SEV_ORDER) => TRACE:5
  s2, c = re.subn(r'(\bINFO\s*:\s*\d+\s*),\s*(\d+)\s*};', r'\1, TRACE:\2};', s); n+=c; s=s2

  return s,n

for f in files:
  if not f.exists():
    print("[SKIP] missing", f); continue
  s=f.read_text(encoding="utf-8", errors="replace")
  if "P61_FIX_TRACE_SYNTAX_LOADED_V1" in s:
    print("[OK] already patched", f); continue
  s2, n = patch_text(s)
  if n==0:
    print("[WARN] no patterns matched", f)
    continue
  bak=f.with_suffix(f.suffix + f".bak_p61_{TS}")
  bak.write_text(s, encoding="utf-8")
  f.write_text("/* P61_FIX_TRACE_SYNTAX_LOADED_V1 */\n"+s2, encoding="utf-8")
  print("[OK] patched", f, "changes=", n, "backup=", bak)
PY

echo "== node --check (after) =="
node --check static/js/vsp_bundle_tabs5_v1.js
node --check static/js/vsp_dashboard_luxe_v1.js
echo "[DONE] P61 ok"
