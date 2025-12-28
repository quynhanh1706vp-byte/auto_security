#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_guessci_v33_findoutci_v3_${TS}"
echo "[BACKUP] $F.bak_guessci_v33_findoutci_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

path = Path("vsp_demo_app.py")
t = path.read_text(encoding="utf-8", errors="ignore")

FN  = "_vsp_guess_ci_run_dir_from_rid_v33"
TAG = "# === VSP_GUESS_CI_RUN_DIR_V33_FIND_OUT_CI_V3 ==="

# Find function def line robustly (ignore arg names, type hints, return hints)
m = re.search(r'(?m)^(?P<indent>\s*)def\s+' + re.escape(FN) + r'\s*\([^)]*\)\s*(?:->\s*[^:]+)?\s*:\s*$', t)
if not m:
    # debug: list available guess funcs
    found = re.findall(r'(?m)^\s*def\s+(_vsp_guess_ci_run_dir_from_rid_v\d+)\s*\(', t)
    print("[ERR] cannot find function:", FN)
    print("[HINT] available guess funcs:", found[-10:])
    raise SystemExit(2)

indent = m.group("indent")
start = m.start()

# Find end of this function: next "def" at same indent level (or EOF)
m_next = re.search(r'(?m)^' + re.escape(indent) + r'def\s+\w+\s*\(', t[m.end():])
end = (m.end() + m_next.start()) if m_next else len(t)

fn = t[start:end]
if TAG in fn:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# Insert after optional docstring
def _insert_after_docstring(block: str) -> int:
    # find first line after def
    first_nl = block.find("\n")
    if first_nl < 0:
        return len(block)
    body = block[first_nl+1:]
    # detect docstring at top of body
    mdoc = re.match(r'(\s*)(?P<q>"""|\'\'\')', body)
    if not mdoc:
        return first_nl+1
    q = mdoc.group("q")
    # find closing q after start
    close = body.find(q, mdoc.end())
    if close < 0:
        return first_nl+1
    # move to end of that line
    nl = body.find("\n", close + len(q))
    if nl < 0:
        return first_nl+1
    return first_nl+1 + nl + 1

ins = _insert_after_docstring(fn)

# Determine body indent (default 4 spaces more than def indent)
body_indent = indent + "    "

inject = (
    "\n"
    f"{body_indent}{TAG}\n"
    f"{body_indent}try:\n"
    f"{body_indent}    from pathlib import Path as _Path\n"
    f"{body_indent}    rn = (rid_norm or '').strip()\n"
    f"{body_indent}    if rn.startswith('RUN_'):\n"
    f"{body_indent}        rn = rn[4:].strip()\n"
    f"{body_indent}\n"
    f"{body_indent}    base = _Path('/home/test/Data')\n"
    f"{body_indent}\n"
    f"{body_indent}    # fast-path known layout\n"
    f"{body_indent}    cand = base / 'SECURITY-10-10-v4' / 'out_ci' / rn\n"
    f"{body_indent}    if cand.is_dir():\n"
    f"{body_indent}        return str(cand)\n"
    f"{body_indent}\n"
    f"{body_indent}    # generic shallow search (no ** recursion)\n"
    f"{body_indent}    pats = (\n"
    f"{body_indent}        '*/out_ci/' + rn,\n"
    f"{body_indent}        '*/*/out_ci/' + rn,\n"
    f"{body_indent}        '*/*/*/out_ci/' + rn,\n"
    f"{body_indent}    )\n"
    f"{body_indent}    for pat in pats:\n"
    f"{body_indent}        for c in base.glob(pat):\n"
    f"{body_indent}            if c.is_dir():\n"
    f"{body_indent}                return str(c)\n"
    f"{body_indent}except Exception:\n"
    f"{body_indent}    pass\n"
)

fn2 = fn[:ins] + inject + fn[ins:]
t2 = t[:start] + fn2 + t[end:]
path.write_text(t2, encoding="utf-8")
print("[OK] patched", FN)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] run_status_v2 should now include ci_run_dir + kics_* =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
