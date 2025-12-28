#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need sed; need grep

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_fix_except_stuck_${TS}"
echo "[BACKUP] ${GW}.bak_fix_except_stuck_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Fix patterns like: "<code>)except Exception:" or "<code>) except:"
# Keep indentation of the original line for 'except'.
pat = re.compile(r'(?m)^(?P<indent>[ \t]*)(?P<stmt>.*\))\s*except(?P<rest>\s*(?:Exception|BaseException|Exception\s+as\s+\w+)?\s*:)')
s2, n = pat.subn(lambda m: f"{m.group('indent')}{m.group('stmt')}\n{m.group('indent')}except{m.group('rest')}", s)

# Also handle "}except" edge case (rare)
pat2 = re.compile(r'(?m)^(?P<indent>[ \t]*)(?P<stmt>.*\})\s*except(?P<rest>.*:)\s*$')
s2, n2 = pat2.subn(lambda m: f"{m.group('indent')}{m.group('stmt')}\n{m.group('indent')}except{m.group('rest')}", s2)

p.write_text(s2, encoding="utf-8")
print(f"[OK] fixed stuck-except occurrences: {n+n2}")
PY

echo "== show around line 450-470 =="
nl -ba "$GW" | sed -n '440,475p'

echo "== py_compile =="
python3 -m py_compile "$GW" && echo "[OK] py_compile OK"
