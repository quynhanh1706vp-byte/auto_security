#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "${APP}.bak_fix_except_${TS}"
echo "[BACKUP] ${APP}.bak_fix_except_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

def indent(s: str) -> int:
    return len(s) - len(s.lstrip(" "))

def is_blank_or_comment(s: str) -> bool:
    t = s.strip()
    return (t == "") or t.startswith("#")

changed = 0
out = []
i = 0
while i < len(lines):
    line = lines[i]
    out.append(line)

    # match: except ...:
    if re.match(r'^\s*except\b.*:\s*$', line):
        ex_ind = indent(line)
        # find next non-blank/non-comment line
        j = i + 1
        while j < len(lines) and is_blank_or_comment(lines[j]):
            j += 1
        # If next meaningful line is not more indented => missing block
        if j >= len(lines) or indent(lines[j]) <= ex_ind:
            out.append(" " * (ex_ind + 4) + "pass  # AUTO-FIX: dangling except\n")
            changed += 1

    i += 1

p.write_text("".join(out), encoding="utf-8")
print("[OK] fixed_dangling_except=", changed)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile: vsp_demo_app.py"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi
