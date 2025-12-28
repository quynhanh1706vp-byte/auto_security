#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need grep; need sed; need date

python3 - <<'PY'
from pathlib import Path
import re, sys

ROOT = Path(".")
# scan likely files first
cands = []
for p in [ROOT/"vsp_demo_app.py", ROOT/"wsgi_vsp_ui_gateway.py"]:
    if p.exists(): cands.append(p)
# plus any py under ui root (shallow)
for p in sorted(ROOT.glob("*.py")):
    if p not in cands:
        cands.append(p)

hits = []
for p in cands:
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    # look for run_file / run_file2 routes or handlers
    if ("/api/vsp/run_file" in s) or ("run_file2" in s) or ("def run_file" in s):
        hits.append((p, s))

if not hits:
    print("[ERR] cannot find run_file handler in top-level *.py")
    sys.exit(2)

# pick best: file that has route decorator for /api/vsp/run_file or /api/vsp/run_file2
best = None
for p, s in hits:
    if re.search(r'@app\.route\(\s*[\'"]/api/vsp/run_file2', s):
        best = (p, s); break
for p, s in hits:
    if best: break
    if re.search(r'@app\.route\(\s*[\'"]/api/vsp/run_file', s):
        best = (p, s); break
if not best:
    best = hits[0]

p, s = best
MARK = "VSP_RUN_FILE_ALLOW_SUMMARY_P0_V1"
if MARK in s:
    print("[SKIP] already patched:", p)
    sys.exit(0)

# We will inject right after reading `name` from request.args (canonical)
# Find first occurrence of: name = request.args.get('name')  (or "name")
m = re.search(r'^\s*name\s*=\s*request\.args\.get\(\s*[\'"]name[\'"]\s*\).*$', s, flags=re.M)
if not m:
    # fallback: locate rid then name nearby
    m = re.search(r'^\s*rid\s*=\s*request\.args\.get\(\s*[\'"]rid[\'"]\s*\).*$', s, flags=re.M)
    if not m:
        print("[ERR] cannot locate name/rid parsing to inject safely in", p)
        sys.exit(3)
    # inject after this rid line (still ok)
    ins_pos = m.end()
    indent = re.match(r'^(\s*)', m.group(0)).group(1)
else:
    ins_pos = m.end()
    indent = re.match(r'^(\s*)', m.group(0)).group(1)

inject = f"""
{indent}# {MARK}
{indent}# Normalize SUMMARY.txt to reports/SUMMARY.txt (commercial: keep whitelist tight, but allow this common artifact)
{indent}try:
{indent}    _n = (name or "").strip()
{indent}    if _n == "SUMMARY.txt":
{indent}        name = "reports/SUMMARY.txt"
{indent}except Exception:
{indent}    pass
"""

s2 = s[:ins_pos] + inject + s[ins_pos:]

# Also expand whitelist if we can spot it (best-effort):
# Add reports/SUMMARY.txt to any list/set/tuple literal containing known allowed files.
# Typical allowed tokens we saw: reports/index.html, reports/run_gate_summary.json, reports/findings_unified.json
if "reports/SUMMARY.txt" not in s2:
    pat = r'(reports/index\.html[\'"]\s*,\s*[\'"]reports/run_gate_summary\.json[\'"]\s*,\s*[\'"]reports/findings_unified\.json)'
    s2 = re.sub(pat, r'\1, "reports/SUMMARY.txt"', s2, count=1)

Path(p).write_text(s2, encoding="utf-8")
print("[OK] patched:", p)
PY

# show which file patched
echo "[INFO] patched file:"
grep -R --line-number "VSP_RUN_FILE_ALLOW_SUMMARY_P0_V1" -n /home/test/Data/SECURITY_BUNDLE/ui/*.py || true

# sanity compile likely app file (compile all top-level py to be safe)
python3 - <<'PY'
import py_compile, glob
ok=0
for f in glob.glob("/home/test/Data/SECURITY_BUNDLE/ui/*.py"):
    try:
        py_compile.compile(f, doraise=True)
        ok+=1
    except Exception as e:
        print("[ERR] py_compile:", f, e)
        raise
print("[OK] py_compile top-level py:", ok)
PY

echo "[NEXT] restart service"
sudo systemctl restart vsp-ui-8910.service
sleep 0.7
curl -sS -I http://127.0.0.1:8910/vsp5 | head -n 12
