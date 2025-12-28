#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_rfallow_items_${TS}"
echo "[BACKUP] ${WSGI}.bak_rfallow_items_${TS}"

python3 - "$WSGI" <<'PY'
import sys,re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P0_RUN_FILE_ALLOW_ITEMS_TO_FINDINGS_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# locate run_file_allow area
i = s.find('"/api/vsp/run_file_allow"')
if i < 0:
    i = s.find("/api/vsp/run_file_allow")
if i < 0:
    i = s.find("run_file_allow")
if i < 0:
    print("[ERR] cannot locate run_file_allow region")
    raise SystemExit(2)

window = s[i:i+30000]

# find json load(s) assignment
m = re.search(r'(?m)^(?P<ind>\s*)(?P<var>\w+)\s*=\s*json\.(load|loads)\s*\(', window)
if not m:
    print("[ERR] cannot find json.load/loads assignment near run_file_allow")
    raise SystemExit(2)

ind = m.group("ind")
var = m.group("var")
abs_pos = i + m.start()
line_end = s.find("\n", abs_pos)
if line_end < 0:
    print("[ERR] unexpected EOF")
    raise SystemExit(2)

inject = (
"\n"
f"{ind}# {marker}\n"
f"{ind}# Some unified findings files use top-level key 'items' (or 'data').\n"
f"{ind}# Normalize to 'findings' so pagination/UI remains consistent.\n"
f"{ind}if isinstance({var}, dict):\n"
f"{ind}    _f = {var}.get('findings')\n"
f"{ind}    if (not isinstance(_f, list)) or (len(_f)==0):\n"
f"{ind}        for _alt in ('items','data'):\n"
f"{ind}            _v = {var}.get(_alt)\n"
f"{ind}            if isinstance(_v, list) and len(_v)>0:\n"
f"{ind}                {var}['findings'] = _v\n"
f"{ind}                break\n"
)

s2 = s[:line_end+1] + inject + s[line_end+1:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched run_file_allow: items/data -> findings fallback")
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" || true
echo "[OK] restarted (if service exists)"

grep -n "VSP_P0_RUN_FILE_ALLOW_ITEMS_TO_FINDINGS_V1" "$WSGI" | head -n 3 || true
