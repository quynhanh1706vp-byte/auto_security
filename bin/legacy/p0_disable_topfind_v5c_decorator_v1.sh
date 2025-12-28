#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_disable_topfind_v5c_${TS}"
echo "[BACKUP] ${W}.bak_disable_topfind_v5c_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Comment out ONLY the decorator line that registers v5c on `app.route(...)`
pat = r'(?m)^\s*@app\.route\([^\n]*endpoint\s*=\s*["\']vsp_top_findings_v1_gateway_v5c["\'][^\n]*\)\s*$'
if not re.search(pat, s):
    print("[OK] no v5c decorator found (nothing to do)")
    sys.exit(0)

s2 = re.sub(pat, '# [DISABLED] v5c topfind decorator (app may be MW without .route)', s)
p.write_text(s2, encoding="utf-8")
print("[OK] disabled v5c decorator line")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
sudo systemctl restart vsp-ui-8910.service
sudo systemctl is-active --quiet vsp-ui-8910.service && echo "[OK] service active"

BASE="http://127.0.0.1:8910"
curl -fsS "$BASE/api/vsp/top_findings_v1?limit=5" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid_used=",j.get("rid_used"),"total=",j.get("total"))'
