#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixquote_${TS}"
echo "[BACKUP] ${F}.bak_fixquote_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# Fix the broken pattern: "<script src="/static/js/...js\"></script>\n"
# Convert to safe single-quoted HTML attribute inside the Python double-quoted string.
def fix_one(s: str):
    # Pattern with escaped quote before ></script>
    s2, n = re.subn(
        r'"<script src="/static/js/([^"]+?)\\"></script>\\n"',
        r'"<script src=\'/static/js/\1\'></script>\\n"',
        s
    )
    if n:
        return s2, n

    # Exact filename fallback (most likely culprit)
    target = '"<script src="/static/js/vsp_fill_real_data_5tabs_p1_v1.js\\"></script>\\n"'
    repl   = '"<script src=\'/static/js/vsp_fill_real_data_5tabs_p1_v1.js\'></script>\\n"'
    if target in s:
        return s.replace(target, repl), 1

    # Another fallback: if someone inserted without escaping but still wrong quoting
    s3, n2 = re.subn(
        r'"<script src="/static/js/([^"]+?)"></script>\\n"',
        r'"<script src=\'/static/js/\1\'></script>\\n"',
        s
    )
    return s3, n2

s_fixed, n = fix_one(s)

if n == 0:
    print("[ERR] did not find the broken <script src=\"/static/js/...\\\"> pattern to fix.")
    print("[HINT] show the surrounding lines:")
    # show around line 483-ish
    lines = s.splitlines()
    for i in range(max(0, 483-15), min(len(lines), 483+15)):
        print(f"{i+1:5d} | {lines[i]}")
    sys.exit(3)

p.write_text(s_fixed, encoding="utf-8")
print(f"[OK] patched occurrences: {n}")

# sanity: ensure no remaining '<script src="/static/js/' inside a Python double-quoted string that would break syntax
# (we only check for the specific broken sequence src="/static/js/...\" pattern)
if 'src="/static/js/' in s_fixed:
    # This is allowed in HTML, but not if it's inside a Python "..." literal without escaping.
    # We leave it as a warning because other strings might be triple-quoted etc.
    print("[WARN] found 'src=\"/static/js/' occurrences remain. Ensure they are not inside Python double-quoted literals.")
PY

echo "== GATE: py_compile (must PASS) =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
