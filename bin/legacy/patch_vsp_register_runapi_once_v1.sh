#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_regonce_${TS}"
echo "[BACKUP] $F.bak_regonce_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
txt=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_REGISTER_RUNAPI_ONCE_V1" in txt:
    print("[SKIP] already patched")
    raise SystemExit(0)

# Heuristic: find the log string "[VSP_RUN_API] OK registered:" and wrap the whole nearby block.
pos = txt.find("[VSP_RUN_API] OK registered:")
if pos == -1:
    raise SystemExit("[ERR] cannot find '[VSP_RUN_API] OK registered:' in vsp_demo_app.py")

# Find start of the statement line containing that print
line_start = txt.rfind("\n", 0, pos) + 1
# Expand upward a bit to include registration code (up to 30 lines)
up_start = txt.rfind("\n", 0, max(0, line_start-2000))
if up_start == -1: up_start = 0

chunk = txt[up_start:line_start]
# Find last blank line boundary as a safer insertion point
ins = up_start + (chunk.rfind("\n\n") + 2 if "\n\n" in chunk else 0)

guard = r'''
# === VSP_REGISTER_RUNAPI_ONCE_V1 ===
if globals().get("VSP_RUN_API_REGISTERED_ONCE"):
  pass
else:
  globals()["VSP_RUN_API_REGISTERED_ONCE"] = True
# === END VSP_REGISTER_RUNAPI_ONCE_V1 ===
'''.lstrip("\n")

# Indent subsequent registration block by two spaces if it’s at top-level.
# We’ll simply insert guard and also indent the next ~120 lines until after the OK registered print line.
# Simpler & safe: only guard prints by early return? Not possible at module-level.
# So: we indent a detected block starting at 'try:' nearest after insertion until after OK registered print line.

# Find the next "try:" after insertion (module-level register is usually in try/except)
try_pos = txt.find("\ntry:", ins)
if try_pos == -1 or try_pos > pos:
    # fallback: just insert guard right before the print line (minimal impact)
    txt2 = txt[:line_start] + guard + txt[line_start:]
    p.write_text(txt2, encoding="utf-8")
    print("[OK] inserted guard near print (minimal)")
    raise SystemExit(0)

# Determine block to indent: from try_pos+1 line to a bit after the OK line
end_block = txt.find("\n\n", pos)  # stop at blank line after OK
if end_block == -1:
    end_block = pos + 500

block = txt[try_pos:end_block]
# indent block with two spaces, but keep leading newlines
indented = "\n".join(("  "+ln if ln.strip() else ln) for ln in block.splitlines())

# Replace original block with guarded+indented block
txt2 = txt[:try_pos] + "\n" + guard + indented + txt[end_block:]
p.write_text(txt2, encoding="utf-8")
print("[OK] wrapped run_api registration with register-once guard")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== Log grep (must show OK registered only once) =="
grep -n "VSP_RUN_API" out_ci/ui_8910.log | head -n 20 || true
