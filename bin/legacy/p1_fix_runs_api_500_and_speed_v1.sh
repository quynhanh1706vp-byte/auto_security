#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_runs_reports_bp.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixruns500_speed_${TS}"
echo "[BACKUP] ${F}.bak_fixruns500_speed_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_runs_reports_bp.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_FIX_RUNS500_SPEED_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

# (A) Ensure _has() defines rid (avoid NameError when building sha_path)
m = re.search(r'(?m)^def\s+_has\s*\(\s*([A-Za-z_]\w*)\s*\)\s*:\s*$', s)
if m:
    arg = m.group(1)
    # check first ~15 lines after def
    start = m.end()
    chunk = s[start:start+800]
    if "rid =" not in chunk:
        inject = f"\n    rid = getattr({arg}, 'name', '')\n"
        s = s[:start] + inject + s[start:]
        print("[OK] injected rid into _has()")
else:
    print("[WARN] cannot find def _has(...): skip rid injection")

# (B) Cap /api/vsp/runs limit default small (speed)
# Replace existing limit assignment if found
s2 = re.sub(
    r'(?m)^\s*limit\s*=\s*int\s*\(\s*request\.args\.get\(\s*["\']limit["\']\s*,\s*([0-9]+)\s*\)\s*\)\s*$',
    r'    limit = request.args.get("limit", "")\n'
    r'    try:\n'
    r'        limit = int(limit) if str(limit).strip() else 50\n'
    r'    except Exception:\n'
    r'        limit = 50\n'
    r'    if limit < 1: limit = 1\n'
    r'    if limit > 200: limit = 200\n',
    s
)
s = s2

# If no "limit = int(request.args.get("limit"...)) existed, try to add a cap near api_runs start
if "if limit > 200" not in s:
    m2 = re.search(r'(?m)^def\s+api_runs\s*\(\s*\)\s*:\s*$', s)
    if m2:
        ins = (
            '\n    # '+MARK+': cap for commercial UI performance\n'
            '    limit = request.args.get("limit","")\n'
            '    try:\n'
            '        limit = int(limit) if str(limit).strip() else 50\n'
            '    except Exception:\n'
            '        limit = 50\n'
            '    if limit < 1: limit = 1\n'
            '    if limit > 200: limit = 200\n'
        )
        s = s[:m2.end()] + ins + s[m2.end():]
        print("[OK] injected limit cap into api_runs()")

s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] wrote:", MARK)
PY

python3 -m py_compile vsp_runs_reports_bp.py
echo "[OK] py_compile OK: vsp_runs_reports_bp.py"

sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== smoke: runs must be JSON now =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/runs?limit=1" | head -n 40
