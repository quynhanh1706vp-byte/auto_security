#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need date; need curl; need jq

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_proxy_runfile_v2_${TS}"
echo "[BACKUP] ${F}.bak_proxy_runfile_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_PROXY_RUN_FILE_SUMMARY_TO_RUN_FILE2_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

old = 'if path == "/api/vsp/run_file" and method == "GET":'
new = 'if path == "/api/vsp/run_file" and method in ("GET","HEAD"):'

if old not in s:
    # maybe formatting differs slightly
    s2 = re.sub(r'if\s+path\s*==\s*["\']/api/vsp/run_file["\']\s+and\s+method\s*==\s*["\']GET["\']\s*:',
                'if path == "/api/vsp/run_file" and method in ("GET","HEAD"):',
                s)
    if s2 == s:
        raise SystemExit("[ERR] cannot find proxy GET-only condition to upgrade to HEAD+GET")
    s = s2
else:
    s = s.replace(old, new, 1)

s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] upgraded proxy to handle HEAD:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

sudo systemctl restart vsp-ui-8910.service
sleep 1

BASE="http://127.0.0.1:8910"
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"

echo "== smoke HEAD SUMMARY via legacy run_file (must be 200 now) =="
curl -sS -I "$BASE/api/vsp/run_file?rid=$RID&name=reports/SUMMARY.txt" | head -n 12
