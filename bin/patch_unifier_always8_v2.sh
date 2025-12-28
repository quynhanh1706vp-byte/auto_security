#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/bin/vsp_unify_findings_always8_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fixcodeql_${TS}"
echo "[BACKUP] $F.bak_fixcodeql_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/bin/vsp_unify_findings_always8_v1.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# 1) Force tool uppercase in add()
s = re.sub(
    r'("tool":\s*)tool,',
    r'\1 (tool or "").upper(),',
    s,
    count=1
)

# 2) Narrow CodeQL SARIF search patterns (remove **/*.sarif)
s = re.sub(
    r'find_first\(run_dir,\s*\["codeql/\*\.sarif","\\*\\*/\\*codeql\\*\.sarif","\\*\\*/\\*\.sarif"\]\)',
    'find_first(run_dir, ["codeql/*.sarif","codeql/**/*.sarif","**/codeql/*.sarif","**/codeql/**/*.sarif","**/*codeql*.sarif"])',
    s
)

# If the above exact line didn't match (older text), do a more general replace:
s = s.replace('["codeql/*.sarif","**/*codeql*.sarif","**/*.sarif"]',
              '["codeql/*.sarif","codeql/**/*.sarif","**/codeql/*.sarif","**/codeql/**/*.sarif","**/*codeql*.sarif"]')

# 3) Harden parse_codeql: skip non-dict runs/results
def harden_parse_codeql(txt: str) -> str:
    if "def parse_codeql" not in txt:
        return txt
    # Insert guards inside parse_codeql loops
    txt = re.sub(
        r'for run in \(data\.get\("runs"\) or \[\]\):\n\s*for res in \(run\.get\("results"\) or \[\]\):',
        'for run in (data.get("runs") or []):\n        if not isinstance(run, dict):\n            continue\n        for res in (run.get("results") or []):\n            if not isinstance(res, dict):\n                continue',
        txt
    )
    # Also guard data["runs"] type
    txt = re.sub(
        r'for run in \(data\.get\("runs"\) or \[\]\):',
        'runs = data.get("runs")\n    if not isinstance(runs, list):\n        return\n    for run in (runs or []):',
        txt,
        count=1
    )
    return txt

s2 = harden_parse_codeql(s)

# 4) Make main resilient: wrap each parse_* call in try/except
# Replace the straight calls block with guarded calls
calls_block = r"""
    items = \[\]
    parse_gitleaks\(run_dir, items\)
    parse_semgrep\(run_dir, items\)
    parse_trivy\(run_dir, items\)
    parse_codeql\(run_dir, items\)
    parse_kics\(run_dir, items\)
    parse_grype\(run_dir, items\)
    parse_syft\(run_dir, items\)
    parse_bandit\(run_dir, items\)
"""
guarded = r"""
    items = []
    for fn in [parse_gitleaks, parse_semgrep, parse_trivy, parse_codeql, parse_kics, parse_grype, parse_syft, parse_bandit]:
        try:
            fn(run_dir, items)
        except Exception as e:
            # degrade graceful: keep going, still write unified
            print("[WARN] parser failed:", getattr(fn, "__name__", "unknown"), "err=", str(e))
"""
s2 = re.sub(calls_block, guarded, s2, count=1, flags=re.M)

p.write_text(s2, encoding="utf-8")
print("[OK] patched unifier v2 (codeql hardened + no-crash + tool uppercase)")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile"
echo "[DONE] patched $F"
