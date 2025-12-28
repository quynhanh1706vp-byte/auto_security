#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_runs_reports_bp.py"
[ -f "$F" ] || { echo "[ERR] missing $F (grep: ls -la /home/test/Data/SECURITY_BUNDLE/ui | grep vsp_runs_reports_bp)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_allowsha_${TS}"
echo "[BACKUP] ${F}.bak_allowsha_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_runs_reports_bp.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_BP_RUN_FILE_ALLOW_SHA256SUMS_P1_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# (A) Best: patch allowlist that already contains SUMMARY.txt -> add SHA256SUMS.txt
patched_allowlist=False

# try common patterns: lists/sets/tuples containing SUMMARY.txt
patterns = [
    r'(\[[^\]]*SUMMARY\.txt[^\]]*\])',
    r'(\{[^}]*SUMMARY\.txt[^}]*\})',
    r'(\([^\)]*SUMMARY\.txt[^\)]*\))',
]
for pat in patterns:
    m=re.search(pat, s, flags=re.S)
    if not m:
        continue
    block=m.group(1)
    if "SHA256SUMS.txt" in block:
        patched_allowlist=True
        break
    # insert after SUMMARY.txt token
    new_block=re.sub(r'(SUMMARY\.txt[\'"]?\s*,?)', r'\1 "SHA256SUMS.txt",', block, count=1)
    if new_block!=block:
        s=s.replace(block, new_block, 1)
        patched_allowlist=True
        print("[OK] allowlist extended with SHA256SUMS.txt")
        break

# (B) Fallback: inject safe bypass inside run_file handler
if not patched_allowlist:
    # find handler for /api/vsp/run_file
    idx=s.find("/api/vsp/run_file")
    if idx<0:
        raise SystemExit("[ERR] cannot find /api/vsp/run_file in vsp_runs_reports_bp.py")
    mdef=re.search(r'\n\s*def\s+\w+\s*\([^)]*\)\s*:\s*\n', s[idx:])
    if not mdef:
        raise SystemExit("[ERR] cannot locate handler def after /api/vsp/run_file")

    def_start=idx+mdef.start()
    mend=re.search(r'\n(?:@bp\.|def)\s', s[def_start+1:])
    def_end=(def_start+1+mend.start()) if mend else len(s)
    func=s[def_start:def_end]

    inject=f'''
    # {MARK}: allow serving reports/SHA256SUMS.txt (commercial audit)
    try:
        if str(name) == "reports/SHA256SUMS.txt":
            from pathlib import Path as _P
            from flask import send_file as _send_file, jsonify as _jsonify
            _fp = _P(run_dir) / "reports" / "SHA256SUMS.txt"
            if _fp.exists():
                return _send_file(str(_fp), as_attachment=True)
            return _jsonify({{"ok": False, "err": "missing SHA256SUMS.txt"}}), 404
    except Exception:
        pass
'''

    # inject after first "name =" line (or request.args.get('name'))
    m_name=re.search(r'^\s*name\s*=\s*.*$', func, flags=re.M)
    if m_name:
        pos=m_name.end()
        func2=func[:pos] + "\n" + inject + func[pos:]
    else:
        m_req=re.search(r'request\.args\.get\(\s*[\'"]name[\'"]', func)
        if not m_req:
            raise SystemExit("[ERR] cannot find name extraction in run_file handler")
        line_end = func.find("\n", m_req.start())
        pos = line_end if line_end!=-1 else m_req.end()
        func2=func[:pos] + "\n" + inject + func[pos:]

    s=s[:def_start] + func2 + s[def_end:]
    print("[OK] injected bypass in handler (fallback)")

s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] wrote patch mark:", MARK)
PY

python3 -m py_compile vsp_runs_reports_bp.py
echo "[OK] py_compile OK: vsp_runs_reports_bp.py"

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="$(curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | jq -r '.items[0].run_id')"
echo "RID=$RID"
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 8
