#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p963c_${TS}"
mkdir -p "$OUT"

cp -f "$APP" "$OUT/$(basename "$APP").bak_${TS}"
echo "[OK] backup => $OUT"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Locate the roots list inside _vsp_p963_find_run_dir
pat=re.compile(r"def _vsp_p963_find_run_dir\(rid: str\):\s*\n\s*roots\s*=\s*\[(.*?)\]\s*", re.S)
m=pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find _vsp_p963_find_run_dir roots list")

new_roots = r'''
def _vsp_p963_find_run_dir(rid: str):
    # Prefer SECURITY_BUNDLE outputs first (these have unified findings)
    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
    ]
'''

# Replace the whole function header+roots block up to the closing bracket
s = s[:m.start()] + new_roots + s[m.end():]

p.write_text(s, encoding="utf-8")
print("[OK] reordered roots to prefer SECURITY_BUNDLE/out")
PY

echo "== [compile] =="
python3 -m py_compile "$APP"
echo "[PASS] P963C applied"
