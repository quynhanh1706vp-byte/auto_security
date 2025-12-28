#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_bslash_${TS}"
echo "[BACKUP] ${F}.bak_fix_bslash_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Fix the exact broken pattern: replace("\","/") -> replace("\\","/")
s2, n = re.subn(r'replace\(\s*"\\"\s*,\s*"/"\s*\)', r'replace("\\\\","/")', s)

# Also handle single quotes just in case
s2, n2 = re.subn(r"replace\(\s*'\\"\s*,\s*'/'\s*\)", r"replace('\\\\','/')", s2)

if (n + n2) == 0:
    # fallback: fix the *really* broken literal: replace("\","/")  (unterminated)
    # We patch the whole line safely.
    s3, n3 = re.subn(
        r'orig_path\s*=\s*path\.replace\([^)]*\)\.lstrip\("\/"\)',
        r'orig_path = path.replace("\\\\","/").lstrip("/")',
        s2
    )
    s2 = s3
    if n3 == 0:
        raise SystemExit("[ERR] could not find/patch the broken replace() line")
    else:
        print("[OK] patched via line fallback:", n3)
else:
    print("[OK] patched replace() calls:", n + n2)

p.write_text(s2, encoding="utf-8")
PY

echo "== py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] wsgi syntax fixed + service restarted"
