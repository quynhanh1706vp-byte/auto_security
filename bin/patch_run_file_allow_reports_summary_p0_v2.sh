#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_allow_reports_summary_${TS}"
echo "[BACKUP] ${F}.bak_allow_reports_summary_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_RUN_FILE_ALLOW_REPORTS_SUMMARY_P0_V2"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# 1) add "reports/SUMMARY.txt" into obvious allowlists (best-effort)
#    e.g. sets/tuples that already include reports/index.html etc.
def add_to_allowlist(src: str) -> str:
    # Case A: list/tuple/set literal that contains reports/index.html
    patterns = [
        r'(\breports/index\.html\b[\'"]\s*,\s*[\'"]reports/run_gate_summary\.json[\'"]\s*,\s*[\'"]reports/findings_unified\.json[\'"])',
        r'([\'"]reports/index\.html[\'"][\s\S]{0,200}?[\'"]reports/run_gate_summary\.json[\'"][\s\S]{0,200}?[\'"]reports/findings_unified\.json[\'"])',
    ]
    out = src
    if "reports/SUMMARY.txt" in out:
        return out
    for pat in patterns:
        m = re.search(pat, out)
        if m:
            out = out[:m.end()] + ', "reports/SUMMARY.txt"' + out[m.end():]
            return out
    return out

s1 = add_to_allowlist(s)

# 2) inject a hard allow before any deny/return for run_file
# Find the run_file handler by locating "def" near "/api/vsp/run_file"
m = re.search(r'@app\.route\(\s*[\'"]/api/vsp/run_file[\'"][\s\S]*?\)\s*\n(\s*)def\s+([A-Za-z0-9_]+)\s*\(', s1)
if not m:
    print("[ERR] cannot locate /api/vsp/run_file handler for injection")
    raise SystemExit(2)

func_indent = m.group(1)
func_start = m.end()

# Insert right after name parsing if exists, else near top of function
sub = s1[func_start:]
mn = re.search(r'^\s*name\s*=\s*request\.args\.get\(\s*[\'"]name[\'"]\s*\)[^\n]*$', sub, flags=re.M)
if mn:
    ins_pos = func_start + mn.end()
    indent = re.match(r'^(\s*)', mn.group(0)).group(1)
else:
    ins_pos = func_start
    indent = func_indent + "    "

inject = f"""
{indent}# {MARK}
{indent}# Allow serving reports/SUMMARY.txt (keep whitelist strict, but support this common artifact)
{indent}try:
{indent}    _n = (name or "").strip()
{indent}    if _n in ("SUMMARY.txt", "reports/SUMMARY.txt", "reports/summary.txt", "summary.txt"):
{indent}        name = "reports/SUMMARY.txt"
{indent}except Exception:
{indent}    pass
"""

s2 = s1[:ins_pos] + inject + s1[ins_pos:]

p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py"

sudo systemctl restart vsp-ui-8910.service
sleep 0.8

BASE="http://127.0.0.1:8910"
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"
curl -sS -o /dev/null -w "reports/SUMMARY.txt -> %{http_code}\n" \
  "$BASE/api/vsp/run_file?rid=$RID&name=reports/SUMMARY.txt" || true
