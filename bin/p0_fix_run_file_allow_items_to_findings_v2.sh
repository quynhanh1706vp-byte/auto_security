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
cp -f "$WSGI" "${WSGI}.bak_rfallow_items_v2_${TS}"
echo "[BACKUP] ${WSGI}.bak_rfallow_items_v2_${TS}"

python3 - "$WSGI" <<'PY'
import sys,re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P0_RUN_FILE_ALLOW_ITEMS_TO_FINDINGS_V2"
if marker in s:
    print("[OK] already patched v2")
    raise SystemExit(0)

# Find the run_file_allow region and then patch the FIRST "return jsonify(VAR)" after it
start = s.find("run_file_allow")
if start < 0:
    print("[ERR] cannot find 'run_file_allow' in file")
    raise SystemExit(2)

window = s[start:start+60000]

m = re.search(r'(?m)^(?P<ind>\s*)return\s+jsonify\(\s*(?P<var>[A-Za-z_]\w*)\s*\)\s*$', window)
if not m:
    # sometimes written as: return flask.jsonify(var)
    m = re.search(r'(?m)^(?P<ind>\s*)return\s+[A-Za-z_\.]*jsonify\(\s*(?P<var>[A-Za-z_]\w*)\s*\)\s*$', window)
if not m:
    print("[ERR] cannot locate 'return jsonify(VAR)' near run_file_allow")
    raise SystemExit(2)

ind = m.group("ind")
var = m.group("var")
abs_pos = start + m.start()

inject = (
f"{ind}# {marker}\n"
f"{ind}# Normalize unified findings files that use top-level 'items'/'data' instead of 'findings'.\n"
f"{ind}if isinstance({var}, dict):\n"
f"{ind}    _f = {var}.get('findings')\n"
f"{ind}    if (not isinstance(_f, list)) or (len(_f) == 0):\n"
f"{ind}        for _alt in ('items','data'):\n"
f"{ind}            _v = {var}.get(_alt)\n"
f"{ind}            if isinstance(_v, list) and len(_v) > 0:\n"
f"{ind}                {var}['findings'] = _v\n"
f"{ind}                break\n"
)

s2 = s[:abs_pos] + inject + s[abs_pos:]
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched v2 before return jsonify({var})")
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" || true
echo "[OK] restarted (if service exists)"

grep -n "VSP_P0_RUN_FILE_ALLOW_ITEMS_TO_FINDINGS_V2" "$WSGI" | head -n 3 || true
