#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_bad_rid_404_${TS}"
echo "[BACKUP] ${APP}.bak_bad_rid_404_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Insert mapping before the existing "not found/missing/no such" clause if present
pat = r'(elif\s*\(\s*"not found"\s*in\s*err_l\s*\)\s*or\s*\(\s*"missing"\s*in\s*err_l\s*\)\s*or\s*\(\s*"no such"\s*in\s*err_l\s*\)\s*:?\s*\n\s*http\s*=\s*404)'
m = re.search(pat, s)
if m and "bad rid" not in s[m.start()-200:m.start()+50].lower():
    insert = '            elif ("bad rid" in err_l) or ("unknown rid" in err_l):\n                http = 404\n'
    # find line start of the matched elif
    start = s.rfind("\n", 0, m.start()) + 1
    s = s[:start] + insert + s[start:]
    p.write_text(s, encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    print("[OK] patched mapping: bad rid -> 404")
else:
    print("[OK] pattern not found or already patched; skip")

PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted $SVC (if present)"
