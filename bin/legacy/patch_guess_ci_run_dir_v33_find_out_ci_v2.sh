#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_guessci_v33_findoutci_v2_${TS}"
echo "[BACKUP] $F.bak_guessci_v33_findoutci_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

FN = "_vsp_guess_ci_run_dir_from_rid_v33"
TAG = "# === VSP_GUESS_CI_RUN_DIR_V33_FIND_OUT_CI_V2 ==="

m = re.search(r'(?m)^def\s+' + re.escape(FN) + r'\s*\(\s*rid_norm\s*\)\s*:\s*$', t)
if not m:
    print("[ERR] cannot find function:", FN)
    raise SystemExit(2)

# slice function block
start = m.start()
m2 = re.search(r'(?m)^\s*def\s+', t[m.end():])
end = (m.end() + m2.start()) if m2 else len(t)
fn = t[start:end]

if TAG in fn:
    print("[OK] tag already present in function, skip")
    raise SystemExit(0)

# find insertion point after optional docstring
sig_end = fn.find("\n") + 1
body = fn[sig_end:]

# body indent (first non-empty line)
lines = body.splitlines(True)
indent = "    "
for ln in lines:
    if ln.strip():
        indent = re.match(r'(\s*)', ln).group(1)
        break

ins_off = sig_end

# docstring detection
doc_m = re.match(r'(?s)\s*("""|\'\'\')', body)
if doc_m:
    q = doc_m.group(1)
    # find closing triple quote
    close = body.find(q, doc_m.end())
    if close != -1:
        close2 = body.find("\n", close + len(q))
        if close2 != -1:
            ins_off = sig_end + close2 + 1

inject = f"""\n{indent}{TAG}
{indent}try:
{indent}    from pathlib import Path as _Path
{indent}    rn = (rid_norm or "").strip()
{indent}    if rn.startswith("RUN_"):
{indent}        rn = rn[4:].strip()
{indent}
{indent}    # Quick resolve for CI runs: /home/test/Data/*/out_ci/<RID>
{indent}    base = _Path("/home/test/Data")
{indent}    # fast-path known layout (your main scan root)
{indent}    cand = base / "SECURITY-10-10-v4" / "out_ci" / rn
{indent}    if cand.is_dir():
{indent}        return str(cand)
{indent}
{indent}    # generic shallow search (fast enough, avoids ** recursion)
{indent}    for pat in (f"*/out_ci/{{rn}}", f"*/*/out_ci/{{rn}}", f"*/*/*/out_ci/{{rn}}"):
{indent}        for c in base.glob(pat):
{indent}            if c.is_dir():
{indent}                return str(c)
{indent}except Exception:
{indent}    pass
"""

fn2 = fn[:ins_off] + inject + fn[ins_off:]
t2 = t[:start] + fn2 + t[end:]
p.write_text(t2, encoding="utf-8")
print("[OK] patched", FN, "with shallow out_ci resolver")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] run_status_v2 should now include ci_run_dir + kics_* =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
