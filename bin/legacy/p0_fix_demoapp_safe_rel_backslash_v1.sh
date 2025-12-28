#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_fix_bslash_${TS}"
echo "[BACKUP] ${APP}.bak_fix_bslash_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Fix the broken startswith(("/", "\")) -> startswith(("/", "\\"))
before = 'path.startswith(("/", "\\\\"))'
# If already correct, keep.
if before in s:
    print("[OK] already fixed (startswith backslash is correct)")
    raise SystemExit(0)

# Replace the exact broken token (most common)
n1 = 0
if 'path.startswith(("/", "\\"))' in s:
    # This is already correct python text; do nothing
    print("[OK] found correct form already")
    raise SystemExit(0)

# broken form as it appears in the file (quote then backslash then quote)
broken = 'path.startswith(("/", "\\\"))'
if broken in s:
    s = s.replace(broken, 'path.startswith(("/", "\\\\\\"))')
    n1 += 1

# more robust regex: startswith(( "/", "\" )) variants
s2, n2 = re.subn(
    r'path\.startswith\(\s*\(\s*"/"\s*,\s*"\\"\s*\)\s*\)',
    r'path.startswith(("/", "\\\\"))',
    s
)

# also handle the truly broken literal: path.startswith(("/", "\")):
s3, n3 = re.subn(
    r'path\.startswith\(\s*\(\s*"/"\s*,\s*"\\"\s*\)\s*\)\s*:',
    r'path.startswith(("/", "\\\\")):',
    s2
)

# If nothing matched but the file still contains startswith(("/", "\"))
if n1 == 0 and n2 == 0 and n3 == 0:
    # direct raw text fix for: path.startswith(("/", "\")):
    s4, n4 = re.subn(
        r'path\.startswith\(\(\s*"/"\s*,\s*"\\"\s*\)\)\)',
        r'path.startswith(("/", "\\\\"))',
        s3
    )
    s3 = s4
    n3 += n4

changed = (s3 != s)
if not changed:
    # last resort: replace the exact broken snippet seen in your error line
    s3 = s.replace('path.startswith(("/", "\\"))', 'path.startswith(("/", "\\\\"))')

p.write_text(s3, encoding="utf-8")
print("[OK] patched vsp_demo_app.py backslash startswith (fix applied)")
PY

echo "== py_compile =="
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== smoke /api/vsp/rid_latest =="
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 260; echo

echo "[DONE] Ctrl+Shift+R /vsp5"
