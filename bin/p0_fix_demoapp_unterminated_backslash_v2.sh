#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_fix_unterm_bslash_${TS}"
echo "[BACKUP] ${APP}.bak_fix_unterm_bslash_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# Fix the exact broken pattern: path.startswith(("/", "\"))  (quote backslash quote)
# We replace any occurrence of '", "\"' (i.e., a string literal containing ONLY a backslash but missing escaping)
# with a properly escaped backslash literal: "\\"
def fix_startswith_backslash(text: str) -> tuple[str,int]:
    n = 0

    # Case A: tuple contains "/","\"  (BROKEN)
    # Regex explanation: (",\s*") then a single backslash then closing quote
    pat = re.compile(r'path\.startswith\(\s*\(\s*"/"\s*,\s*"\\"\s*\)\s*\)')
    # Build replacement with *two* backslashes in source: "\\"
    repl = 'path.startswith(("/", "' + "\\\\" + '"))'
    text2, n2 = pat.subn(repl, text)
    n += n2

    # Case B: same but immediately followed by ':' (some code styles)
    pat2 = re.compile(r'path\.startswith\(\s*\(\s*"/"\s*,\s*"\\"\s*\)\s*\)\s*:')
    repl2 = 'path.startswith(("/", "' + "\\\\" + '")):'
    text3, n3 = pat2.subn(repl2, text2)
    n += n3

    # Case C: ultra-specific exact substring seen in your error line
    text4 = text3.replace('path.startswith(("/", "\\"))', 'path.startswith(("/", "' + "\\\\" + '"))')
    if text4 != text3:
        n += 1

    return text4, n

s2, n = fix_startswith_backslash(s)

# As a last resort: if the file still contains the literally broken token "\")):
# patch it by turning "\" into "\\"
if '("\\"))' in s2:  # this string means: ("\")) in file text
    s2 = s2.replace('("\\"))', '("' + "\\\\" + '"))')
    n += 1

if s2 == orig:
    print("[WARN] no changes applied (pattern not found) — showing candidate line(s):")
    for i, line in enumerate(orig.splitlines(), 1):
        if "startswith" in line and "path" in line:
            print(f"  L{i}: {line}")
else:
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] patched occurrences={n}")
PY

echo "== py_compile =="
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke rid_latest (must include rid) =="
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 260; echo
echo "== smoke rid_latest_gate_root (must include rid) =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 260; echo

echo "[DONE] Ctrl+Shift+R /vsp5"
