#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] not found: $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_runsfs_rootfix_${TS}"
echo "[BACKUP] $F.bak_runsfs_rootfix_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

# Fix only inside RUNS_INDEX_FS_V1 block
m = re.search(r'(?s)(# === RUNS_INDEX_FS_V1 ===.*?# === END RUNS_INDEX_FS_V1 ===)', txt)
if not m:
    raise SystemExit("[ERR] RUNS_INDEX_FS_V1 block not found")

blk = m.group(1)

# Replace wrong bundle_root logic with correct bundle_root
# old:
# ui_root = ...parents[1]
# bundle_root = ui_root.parent
# out_dir = bundle_root / "out"
blk2 = re.sub(
    r'ui_root\s*=\s*_Path\(__file__\)\.resolve\(\)\.parents\[1\]\s*#\s*\.\.\./ui\s*\n\s*bundle_root\s*=\s*ui_root\.parent\s*#.*?\n\s*out_dir\s*=\s*bundle_root\s*/\s*"out"\s*',
    'bundle_root = _Path(__file__).resolve().parents[1]  # .../SECURITY_BUNDLE\n    out_dir = bundle_root / "out"\n    ',
    blk
)

# If pattern didn't match (because text slightly different), do a simpler direct replace
if blk2 == blk:
    blk2 = blk.replace(
        "bundle_root = ui_root.parent                    # .../SECURITY_BUNDLE\n    out_dir = bundle_root / \"out\"",
        "bundle_root = ui_root                           # .../SECURITY_BUNDLE\n    out_dir = bundle_root / \"out\""
    )

# Add optional ENV override (commercial)
if "VSP_BUNDLE_ROOT" not in blk2:
    blk2 = blk2.replace(
        "out_dir = bundle_root / \"out\"",
        "bundle_root = _Path(os.environ.get('VSP_BUNDLE_ROOT', str(bundle_root))).resolve()\n    out_dir = bundle_root / \"out\""
    )

txt2 = txt[:m.start(1)] + blk2 + txt[m.end(1):]
p.write_text(txt2, encoding="utf-8")
print("[OK] fixed runsfs out_dir to SECURITY_BUNDLE/out (with ENV override VSP_BUNDLE_ROOT)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] python syntax OK"
