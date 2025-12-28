#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

BAK="${PYF}.bak_fix_findings_reader_syntax_${TS}"
cp -f "$PYF" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<PY
from pathlib import Path
import py_compile

pyf = Path("vsp_demo_app.py")
bak = Path("$BAK")
s = pyf.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RUN_FILE_ALLOW_FINDINGS_READER_V1"
if MARK not in s:
    print("[ERR] marker not found:", MARK)
    raise SystemExit(2)

before = s.count('f""{e}""')
s2 = s.replace('f""{e}""', 'str(e)')
after = s2.count('f""{e}""')

if before == 0:
    # fallback: sometimes it appears as f""{e}"" with spaces around
    s2 = s2.replace('f""{e}""', 'str(e)')

pyf.write_text(s2, encoding="utf-8")
print(f"[OK] replaced bad f-string: occurrences_before={before}, occurrences_after={after}")

try:
    py_compile.compile(str(pyf), doraise=True)
    print("[OK] py_compile:", pyf)
except Exception as e:
    print("[ERR] py_compile failed -> auto-restore backup:", e)
    pyf.write_text(bak.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    py_compile.compile(str(pyf), doraise=True)
    raise
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] fixed syntax + restarted (best-effort): $SVC"
