#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_devport_${TS}"
echo "[BACKUP] $F.bak_devport_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# If already patched, do nothing
if "VSP_DEV_PORT_ENV_V1" in txt:
    print("[OK] already patched")
    raise SystemExit(0)

# Find typical flask run block: if __name__ == "__main__": app.run(...)
m = re.search(r'if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*([\s\S]{0,400})', txt)
if not m:
    print("[ERR] cannot find __main__ block; please paste bottom 40 lines of vsp_demo_app.py")
    raise SystemExit(1)

block = m.group(0)

# Insert env-based host/port just before app.run(...)
ins = (
"\n    # === VSP_DEV_PORT_ENV_V1 ===\n"
"    import os\n"
"    _host = os.environ.get('VSP_UI_BIND') or os.environ.get('HOST') or '127.0.0.1'\n"
"    _port = int(os.environ.get('VSP_UI_PORT') or os.environ.get('PORT') or '8910')\n"
"    # === END VSP_DEV_PORT_ENV_V1 ===\n"
)

# Replace app.run(...) line(s) inside block
block2 = block
# If app.run has explicit port=..., replace with port=_port and host=_host
block2 = re.sub(r'app\.run\(([^)]*)\)',
                lambda mm: 'app.run(' + mm.group(1) + ')',
                block2)

if "app.run" not in block2:
    print("[ERR] __main__ block found but no app.run() inside; paste bottom 60 lines for patching")
    raise SystemExit(1)

# Ensure host/port kwargs are present (simple approach: append if missing)
def patch_run_line(line: str) -> str:
    if "app.run" not in line:
        return line
    # remove existing host/port args (best effort)
    line = re.sub(r'\bhost\s*=\s*[^,)\n]+,?\s*', '', line)
    line = re.sub(r'\bport\s*=\s*[^,)\n]+,?\s*', '', line)
    if line.rstrip().endswith(")"):
        line = line.rstrip()[:-1] + ", host=_host, port=_port)\n"
    return line

lines = block2.splitlines(True)
lines = [patch_run_line(ln) for ln in lines]
block2 = "".join(lines)

# Put ins right after the if __main__ line
block2 = re.sub(r'(if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:)',
                r'\1' + ins, block2, count=1)

txt2 = txt.replace(block, block2)
p.write_text(txt2, encoding="utf-8")
print("[OK] patched __main__ to read VSP_UI_PORT/VSP_UI_BIND")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile"
