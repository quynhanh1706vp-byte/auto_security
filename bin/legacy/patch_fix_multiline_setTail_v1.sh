#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_commercial_panel_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_multiline_setTail_${TS}"
echo "[BACKUP] $F.bak_fix_multiline_setTail_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("static/js/vsp_runs_commercial_panel_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_FIX_MULTILINE_SETTAIL_V1 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# Fix pattern: setTail('...<newline>...');  (newline thật nằm trong single-quote string)
pat = re.compile(r"setTail\(\s*'([^']*?)\n([^']*?)'\s*\)", flags=re.M)

def repl(m):
    a = m.group(1)
    b = m.group(2)
    # Giữ nguyên nội dung, thay newline thật -> \\n
    return "setTail('" + a + "\\n" + b + "')"

t2, n = pat.subn(repl, t)
if n == 0:
    print("[INFO] no multiline setTail() found -> no change")
else:
    t2 = TAG + "\n" + t2
    p.write_text(t2, encoding="utf-8")
    print(f"[OK] fixed multiline setTail(): {n} occurrence(s)")
PY

echo "== node --check =="
node --check "$F"
echo "[OK] done"
