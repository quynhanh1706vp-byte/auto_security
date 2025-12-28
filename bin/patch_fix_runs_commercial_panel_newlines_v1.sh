#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_commercial_panel_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_newlines_${TS}"
echo "[BACKUP] $F.bak_fix_newlines_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("static/js/vsp_runs_commercial_panel_v1.js")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_FIX_STRING_NEWLINES_V1 ==="
if TAG in txt:
    print("[OK] already patched")
    raise SystemExit(0)

# Fix: setTail('...<NEWLINE>');  => setTail('...\\n');
def repl_single(m):
    s = m.group(1)
    # giữ nguyên nội dung, chỉ thay newline thật thành \n
    return "setTail('%s\\\\n');" % s

txt2 = re.sub(
    r"setTail\('([^']*?)\n\s*'\s*\)\s*;",
    repl_single,
    txt,
    flags=re.M
)

# Fix generic: mọi single-quote string literal kiểu '...\n...' (hiếm nhưng cứ xử)
def repl_generic(m):
    return "setTail('%s\\\\n%s');" % (m.group(1), m.group(2))
txt2 = re.sub(
    r"setTail\('([^']*?)\n([^']*?)'\s*\)\s*;",
    repl_generic,
    txt2,
    flags=re.M
)

p.write_text(TAG + "\n" + txt2, encoding="utf-8")
print("[OK] wrote", p)
PY

echo "== node --check =="
node --check "$F"
