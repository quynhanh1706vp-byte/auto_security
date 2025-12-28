#!/usr/bin/env bash
set -euo pipefail
JSF="static/js/vsp_runs_trigger_scan_ui_v3.js"
BK="$JSF.bak_export_mount_$(date +%Y%m%d_%H%M%S)"
cp "$JSF" "$BK"
echo "[BACKUP] $BK"

python3 - << 'PY'
from pathlib import Path
import re
p = Path("static/js/vsp_runs_trigger_scan_ui_v3.js")
txt = p.read_text(encoding="utf-8", errors="ignore")

if "window.VSP_RUNSCAN_MOUNT" in txt:
    print("[SKIP] already exports VSP_RUNSCAN_MOUNT")
    raise SystemExit(0)

# Find the internal mount() function and expose it.
# We'll inject: window.VSP_RUNSCAN_MOUNT = mount;
# right after mount() declaration starts (after function mount(){ ... is defined).
m = re.search(r"\n\s*function\s+mount\s*\(\)\s*\{", txt)
if not m:
    print("[ERR] cannot find function mount() in v3 js")
    raise SystemExit(1)

# Inject export near end, before the retry interval block if exists; easiest append safely.
inject = "\n\n  // Expose mount for hook re-mounting\n  window.VSP_RUNSCAN_MOUNT = mount;\n"
# Put it just before the retry interval block (var n=0, it=setInterval) if present
txt2, n = re.subn(r"\n(\s*var\s+n\s*=0,\s*it\s*=setInterval\()", inject + r"\n\1", txt, count=1)
if n == 0:
    txt2 = txt + inject

p.write_text(txt2, encoding="utf-8")
print("[OK] exported window.VSP_RUNSCAN_MOUNT")
PY
