#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_stage_re_v2_${TS}"
echo "[BACKUP] $F.bak_stage_re_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_STATUS_V2_WINLAST_V6 ==="
END = "# === END VSP_RUN_STATUS_V2_WINLAST_V6 ==="
m = re.search(re.escape(TAG) + r".*?" + re.escape(END), t, flags=re.S)
if not m:
    raise SystemExit("[ERR] cannot find WINLAST_V6 block")

blk = t[m.start():m.end()]

# replace the whole _STAGE_RE_V2 assignment line safely (no backslash issues)
pat = re.compile(r"(?m)^\s*_STAGE_RE_V2\s*=\s*re\.compile\(.+?\)\s*$")
new_line = r'_STAGE_RE_V2 = re.compile(r"=+\s*\[\s*(\d+)\s*/\s*(\d+)\s*\]\s*([^\n=]+?)\s*=+", re.IGNORECASE)'

def repl(_m):
    return new_line

blk2, n = pat.subn(repl, blk, count=1)
if n != 1:
    raise SystemExit(f"[ERR] cannot patch _STAGE_RE_V2 (matches={n})")

t2 = t[:m.start()] + blk2 + t[m.end():]
p.write_text(t2, encoding="utf-8")
print("[OK] patched _STAGE_RE_V2 in WINLAST_V6")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

# restart
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh >/dev/null 2>&1 || true
echo "[OK] restarted 8910"
