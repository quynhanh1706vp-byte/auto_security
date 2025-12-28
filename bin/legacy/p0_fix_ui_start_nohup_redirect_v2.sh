#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p1_ui_8910_single_owner_start_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_nohupredir_${TS}"
echo "[BACKUP] ${F}.bak_nohupredir_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/p1_ui_8910_single_owner_start_v2.sh")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

# find a nohup block and inject redirect on the line that contains '&' (or a line that is exactly '&')
start_idx = None
for i,l in enumerate(lines):
    if re.search(r'^\s*nohup\b', l):
        start_idx = i
        break

if start_idx is None:
    print("[ERR] cannot find nohup line to patch")
    raise SystemExit(2)

end_idx = None
for j in range(start_idx, min(start_idx+80, len(lines))):
    if re.search(r'\&\s*$', lines[j]) or re.match(r'^\s*\&\s*$', lines[j]):
        end_idx = j
        break

if end_idx is None:
    print("[ERR] cannot find '&' line for nohup block")
    raise SystemExit(3)

# patch end line
l = lines[end_idx]
if "out_ci/ui_8910.boot.log" in "".join(lines[start_idx:end_idx+1]):
    print("[OK] redirect already present in nohup block")
else:
    if re.match(r'^\s*\&\s*$', l):
        lines[end_idx] = "  > out_ci/ui_8910.boot.log 2>&1 &\n"
    else:
        # replace trailing & with redirect + &
        lines[end_idx] = re.sub(r'\&\s*$', r'> out_ci/ui_8910.boot.log 2>&1 &\n', l)
    print(f"[OK] injected redirect into nohup block at line {end_idx+1}")

p.write_text("".join(lines), encoding="utf-8")
PY

bash -n "$F"
echo "[OK] bash -n OK"
