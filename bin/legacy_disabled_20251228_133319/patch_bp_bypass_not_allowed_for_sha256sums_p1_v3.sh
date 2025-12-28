#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_runs_reports_bp.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_bypass_notallowed_${TS}"
echo "[BACKUP] ${F}.bak_bypass_notallowed_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_runs_reports_bp.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_BP_BYPASS_NOT_ALLOWED_SHA256SUMS_P1_V3"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Find the return line that emits {"ok":false,"err":"not allowed"}
m = re.search(r'^[ \t]*return[^\n]*not allowed[^\n]*$', s, flags=re.M)
if not m:
    # fallback: find json payload with err not allowed
    m = re.search(r'^[ \t]*return[^\n]*["\']err["\']\s*:\s*["\']not allowed["\'][^\n]*$', s, flags=re.M)

if not m:
    raise SystemExit("[ERR] cannot find the 'not allowed' return line to patch. Run: grep -n \"not allowed\" vsp_runs_reports_bp.py")

inject = f'''
    # {MARK}: allow reports/SHA256SUMS.txt (commercial audit)
    try:
        if str(name) == "reports/SHA256SUMS.txt":
            from pathlib import Path as _P
            from flask import send_file as _send_file
            _fp = _P(run_dir) / "reports" / "SHA256SUMS.txt"
            if _fp.exists():
                return _send_file(str(_fp), as_attachment=True)
    except Exception:
        pass
'''

# Insert just BEFORE the "not allowed" return
pos = m.start()
s = s[:pos] + inject + s[pos:]
s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] injected bypass before not-allowed return:", MARK)
PY

python3 -m py_compile vsp_runs_reports_bp.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="btl86-connector_RUN_20251127_095755_000599"
echo "RID=$RID"
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 20
