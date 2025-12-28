#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_allowsha_${TS}"
echo "[BACKUP] ${APP}.bak_allowsha_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RUN_FILE_ALLOW_SHA256SUMS_BYPASS_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Find the run_file route block
idx = s.find("/api/vsp/run_file")
if idx < 0:
    raise SystemExit("[ERR] cannot find /api/vsp/run_file in vsp_demo_app.py")

# Find the def after that route
mdef = re.search(r'\n\s*def\s+\w+\s*\([^)]*\)\s*:\s*\n', s[idx:])
if not mdef:
    raise SystemExit("[ERR] cannot locate handler def after /api/vsp/run_file")

def_start = idx + mdef.start()
# find end of function: next top-level def or route decorator at column 0
mend = re.search(r'\n(?:@app\.route|def)\s', s[def_start+1:])
def_end = (def_start+1 + mend.start()) if mend else len(s)

func = s[def_start:def_end]

inject = f'''
    # {MARK}: allow serving checksum file (commercial audit)
    try:
        if str(name) == "reports/SHA256SUMS.txt":
            from pathlib import Path as _Path
            from flask import send_file as _send_file
            _fp = _Path(run_dir) / "reports" / "SHA256SUMS.txt"
            if _fp.exists():
                return _send_file(str(_fp), as_attachment=True)
    except Exception:
        pass
'''

# Insert after first "run_dir =" inside the handler (best place)
m_run_dir = re.search(r'^\s*run_dir\s*=\s*.*$', func, flags=re.M)
if m_run_dir:
    pos = m_run_dir.end()
    func2 = func[:pos] + "\n" + inject + func[pos:]
else:
    # fallback: after first "name =" line
    m_name = re.search(r'^\s*name\s*=\s*.*$', func, flags=re.M)
    if not m_name:
        raise SystemExit("[ERR] cannot find run_dir= or name= in run_file handler to inject")
    pos = m_name.end()
    func2 = func[:pos] + "\n" + inject + func[pos:]

s2 = s[:def_start] + func2 + s[def_end:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="$(curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | jq -r '.items[0].run_id')"
echo "RID=$RID"
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 8
