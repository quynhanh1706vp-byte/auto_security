#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_runs_reports_bp.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p1_v4_${TS}"
echo "[BACKUP] ${F}.bak_p1_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_runs_reports_bp.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_FIX_RUNS500_AND_ALLOW_SHA256SUMS_V4"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# --- (1) FIX _has() tuple bug that causes /api/vsp/runs 500 ---
# Replace any variant of: (run_dir/"SUMMARY.txt" "SHA256SUMS.txt",).exists()
bug_pat = re.compile(
    r'\(\s*run_dir\s*/\s*([\'"])SUMMARY\.txt\1\s*([\'"])SHA256SUMS\.txt\2\s*,\s*\)\s*\.exists\(\)',
    flags=re.M
)
if bug_pat.search(s):
    s = bug_pat.sub(
        r'((run_dir/"SUMMARY.txt").exists() or (run_dir/"reports/SUMMARY.txt").exists())',
        s
    )
    print("[OK] fixed tuple .exists() bug in _has()")
else:
    # also handle the exact broken text that appeared in traceback (more literal)
    s2 = s.replace(
        '(run_dir/"SUMMARY.txt" "SHA256SUMS.txt",).exists()',
        '((run_dir/"SUMMARY.txt").exists() or (run_dir/"reports/SUMMARY.txt").exists())'
    )
    if s2 != s:
        s = s2
        print("[OK] fixed literal tuple .exists() bug in _has()")

# Optional: add explicit sha256sums flag in has dict if not already present (safe additive)
if "sha256sums" not in s:
    # try to inject near 'summary' key inside _has dict
    s = re.sub(
        r'(\n\s*[\'"]summary[\'"]\s*:\s*[^,\n]+,\s*)',
        r'\1' + '\n        "sha256sums": ((run_dir/"SHA256SUMS.txt").exists() or (run_dir/"reports/SHA256SUMS.txt").exists()),\n',
        s,
        count=1
    )

# --- (2) BYPASS allowlist for reports/SHA256SUMS.txt in run_file handler ---
idx = s.find("/api/vsp/run_file")
if idx < 0:
    raise SystemExit("[ERR] cannot find /api/vsp/run_file in blueprint")

mdef = re.search(r'\n\s*def\s+\w+\s*\([^)]*\)\s*:\s*\n', s[idx:])
if not mdef:
    raise SystemExit("[ERR] cannot locate handler def after /api/vsp/run_file")

def_start = idx + mdef.start()
mend = re.search(r'\n(?:@bp\.route|@bp\.get|def)\s', s[def_start+1:])
def_end = (def_start+1 + mend.start()) if mend else len(s)
func = s[def_start:def_end]

BYP = "VSP_P1_RUN_FILE_BYPASS_SHA256SUMS_V4"
if BYP not in s:
    # insert after first "run_dir =" line (so run_dir is available)
    m_run_dir = re.search(r'^\s*run_dir\s*=\s*.*$', func, flags=re.M)
    if not m_run_dir:
        # fallback: insert after first "rid =" line
        m_run_dir = re.search(r'^\s*rid\s*=\s*.*$', func, flags=re.M)
        if not m_run_dir:
            raise SystemExit("[ERR] cannot find run_dir= or rid= anchor in run_file handler")

    inject = f'''
    # {BYP}: allow serving reports/SHA256SUMS.txt regardless of allowlist (commercial audit)
    try:
        _n = request.args.get("name", "") or ""
        if str(_n) == "reports/SHA256SUMS.txt":
            from pathlib import Path as _P
            from flask import send_file as _send_file, jsonify as _jsonify
            _rd = _P(run_dir)
            # support both layouts: run_dir is RUN root or already reports/
            _cand = [
                _rd / "reports" / "SHA256SUMS.txt",
                _rd / "SHA256SUMS.txt",
            ]
            for _fp in _cand:
                if _fp.exists():
                    return _send_file(str(_fp), as_attachment=True)
            return _jsonify({{"ok": False, "err": "missing SHA256SUMS.txt"}}), 404
    except Exception:
        pass
'''

    pos = m_run_dir.end()
    func2 = func[:pos] + "\n" + inject + func[pos:]
    s = s[:def_start] + func2 + s[def_end:]
    print("[OK] injected run_file bypass for SHA256SUMS")

s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] wrote patch mark:", MARK)
PY

python3 -m py_compile vsp_runs_reports_bp.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== smoke: /api/vsp/runs should be JSON (not 500) =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/runs?limit=1" | head -n 25

echo "== smoke: SHA256SUMS allowed now =="
RID="btl86-connector_RUN_20251127_095755_000599"
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 20
