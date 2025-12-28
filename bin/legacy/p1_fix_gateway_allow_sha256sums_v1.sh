#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_allowsha_fix_${TS}"
echo "[BACKUP] ${F}.bak_allowsha_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_ALLOW_SHA256SUMS_GATEWAY_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

orig=s
changed=False

# (A) If whitelist is a list/set/tuple containing reports/SUMMARY.txt, append reports/SHA256SUMS.txt
if "reports/SUMMARY.txt" in s and "reports/SHA256SUMS.txt" not in s:
    s = s.replace('"reports/SUMMARY.txt"', '"reports/SUMMARY.txt", "reports/SHA256SUMS.txt"', 1)
    s = s.replace("'reports/SUMMARY.txt'", "'reports/SUMMARY.txt', 'reports/SHA256SUMS.txt'", 1)
    changed = (s != orig) or changed

# (B) If whitelist is basename-based (SUMMARY.txt), append SHA256SUMS.txt
orig2=s
if "SUMMARY.txt" in s and "SHA256SUMS.txt" not in s:
    s = s.replace('"SUMMARY.txt"', '"SUMMARY.txt", "SHA256SUMS.txt"', 1)
    s = s.replace("'SUMMARY.txt'", "'SUMMARY.txt', 'SHA256SUMS.txt'", 1)
    changed = (s != orig2) or changed

# (C) If allowlist is regex based, extend SUMMARY\.txt to include SHA256SUMS\.txt
# Examples handled:
#   ( ... |SUMMARY\.txt )
#   (SUMMARY\.txt)
orig3=s
s = re.sub(r'(SUMMARY\\\.txt)(?!\|SHA256SUMS\\\.txt)', r'\1|SHA256SUMS\\\.txt', s)
changed = (s != orig3) or changed

if not changed:
    raise SystemExit("[ERR] could not find any allowlist/regex anchor to extend (need to inspect allowlist block)")

s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched gateway allowlist/regex:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK: wsgi_vsp_ui_gateway.py"

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="$(curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | python3 -c 'import sys,json; print(json.load(sys.stdin)["items"][0]["run_id"])')"
echo "RID=$RID"

echo "== smoke legacy run_file (expect 200) =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 12

echo "== smoke run_file2 direct (expect 200 if rewrite uses run_file2 whitelist) =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file2?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 12 || true
