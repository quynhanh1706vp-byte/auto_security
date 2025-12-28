#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_autosha_${TS}"
echo "[BACKUP] ${F}.bak_autosha_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_AUTOGEN_SHA256SUMS_ON_SERVE_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) inject helper near top-level helpers (best-effort: after imports)
helper = r'''
# === {MARK} ===
def _vsp_ensure_reports_sha256sums(run_dir):
    """
    Ensure reports/SHA256SUMS.txt exists (commercial audit).
    Safe no-op if reports missing or nothing to hash.
    """
    try:
        from pathlib import Path
        import hashlib
        rd = Path(run_dir)
        reports = rd / "reports"
        if not reports.exists():
            return None
        sums = reports / "SHA256SUMS.txt"
        if sums.exists() and sums.stat().st_size > 0:
            return str(sums)

        core = ["index.html","run_gate_summary.json","findings_unified.json","SUMMARY.txt"]
        lines=[]
        for fn in core:
            fp = reports / fn
            if fp.exists():
                h = hashlib.sha256(fp.read_bytes()).hexdigest()
                lines.append(f"{h}  {fn}")
        if not lines:
            return None
        sums.write_text("\\n".join(lines) + "\\n", encoding="utf-8")
        return str(sums)
    except Exception:
        return None
# === /{MARK} ===
'''.replace("{MARK}", MARK)

# place helper after the last import block (heuristic)
m = list(re.finditer(r'^(import .+|from .+ import .+)\s*$', s, flags=re.M))
ins_at = m[-1].end() if m else 0
s = s[:ins_at] + "\n" + helper + "\n" + s[ins_at:]

# 2) hook into run_file route when requesting SHA256SUMS
# heuristic: find run_file handler and inject before send_file/return
# We match the route decorator or function name containing "run_file"
pat = r'(@app\.route\([^\n]*?/api/vsp/run_file[^\n]*\)\s*\ndef\s+[A-Za-z0-9_]+\([^)]*\):)'
mm = re.search(pat, s, flags=re.M)
if not mm:
    # fallback: search for def containing run_file
    mm = re.search(r'^\s*def\s+([A-Za-z0-9_]*run_file[A-Za-z0-9_]*)\s*\(', s, flags=re.M)
if not mm:
    print("[ERR] cannot find run_file endpoint to hook. Please grep for /api/vsp/run_file in vsp_demo_app.py")
    raise SystemExit(3)

# inject inside handler: right after it resolves run_dir + name
# We'll inject a lightweight guard near first occurrence of "name =" or request.args.get('name')
inject = f'''
    # {MARK}: auto-generate reports/SHA256SUMS.txt on demand
    try:
        if str(name) == "reports/SHA256SUMS.txt":
            _vsp_ensure_reports_sha256sums(run_dir)
    except Exception:
        pass
'''

# find a good anchor: after line that assigns "name"
anchor = re.search(r'^\s*name\s*=\s*.*$', s, flags=re.M)
if anchor:
    # insert after first name assignment within file (acceptable)
    pos = anchor.end()
    s = s[:pos] + "\n" + inject + s[pos:]
else:
    # fallback: insert near first request.args.get('name')
    anchor = re.search(r'request\.args\.get\(\s*[\'"]name[\'"]', s)
    if not anchor:
        print("[ERR] cannot find name extraction in run_file handler")
        raise SystemExit(4)
    # insert after the line containing request.args.get('name')
    line_start = s.rfind("\n", 0, anchor.start())
    line_end = s.find("\n", anchor.start())
    pos = line_end if line_end!=-1 else anchor.end()
    s = s[:pos] + "\n" + inject + s[pos:]

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1

/home/test/Data/SECURITY_BUNDLE/ui/bin/p1_fast_verify_vsp_ui_v1.sh
