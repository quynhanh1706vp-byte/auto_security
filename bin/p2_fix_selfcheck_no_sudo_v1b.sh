#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p2_ui_state_selfcheck_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_nosudo_v1b_${TS}"
echo "[BACKUP] ${F}.bak_nosudo_v1b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/p2_ui_state_selfcheck_v1.sh")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Remove sudo in front of journalctl (avoid password prompt)
s2 = re.sub(r'(^\s*)sudo\s+(journalctl\b)', r'\1\2', s, flags=re.M)

# 2) For any remaining journalctl line, append "|| echo [SKIP]"
def repl(m):
    line = m.group(0)
    # keep existing '|| true' or pipe; just ensure no prompt and no fail
    if "SKIP" in line:
        return line
    return line + ' || echo "[SKIP] journalctl not permitted (no sudo)"'

s3 = re.sub(r'^\s*journalctl\b.*$', repl, s2, flags=re.M)

changed = (s3 != s)
p.write_text(s3, encoding="utf-8")
print("[OK] patched nosudo_v1b, changed=", changed)
PY

echo
echo "== QUICK GREP after patch =="
grep -n "sudo journalctl" -n "$F" || echo "[OK] no sudo journalctl"
grep -n "journalctl" -n "$F" | head -n 10 || echo "[OK] no journalctl"

echo
echo "== RUN selfcheck =="
bash "$F" | tail -n 40
