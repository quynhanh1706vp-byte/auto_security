#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_harden_tag_${TS}"
echo "[BACKUP] ${F}.bak_harden_tag_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Normalize the exact tag line to a safe variant (single quotes in HTML attribute)
bad1 = '<script src="/static/js/vsp_fill_real_data_5tabs_p1_v1.js"></script>'
bad2 = '<script src=\\"/static/js/vsp_fill_real_data_5tabs_p1_v1.js\\"></script>'
good = "<script src='/static/js/vsp_fill_real_data_5tabs_p1_v1.js'></script>"

# Replace either representation inside the python string block
s2 = s.replace(bad1, good).replace(bad2, good)

if s2 == s:
    # last-resort: rewrite the whole line containing vsp_fill_real_data_5tabs_p1_v1.js
    s3, n = re.subn(
        r'^[ \t]*"<script src=.*vsp_fill_real_data_5tabs_p1_v1\.js.*</script>\\n"\s*$',
        f'                        "{good}\\\\n"\n',
        s,
        flags=re.M
    )
    if n == 0:
        print("[ERR] did not find tag line to harden.")
        sys.exit(3)
    s2 = s3
    print(f"[OK] hardened by regex lines: {n}")
else:
    print("[OK] hardened by direct replace")

p.write_text(s2, encoding="utf-8")
PY

echo "== GATE: py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
