#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

python3 - <<'PY'
from pathlib import Path
import re, time, sys

ROOT = Path(".")
EXCL = {"out","out_ci","node_modules","bin",".venv","venv",".git","__pycache__"}

def ok_path(p: Path) -> bool:
    for part in p.parts:
        if part in EXCL: return False
    return p.suffix == ".py"

# 1) pick best target file that defines /api/vsp/run_file_allow
cands=[]
for p in ROOT.rglob("*.py"):
    if not ok_path(p): 
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    if "run_file_allow" in s and "/api/vsp" in s:
        score = 0
        score += s.count("run_file_allow")*10
        score += s.count("not allowed")*2
        score += s.count("findings_unified.json")*5
        score += 50 if p.name == "wsgi_vsp_ui_gateway.py" else 0
        cands.append((score,p,s))

cands.sort(key=lambda x: x[0], reverse=True)
if not cands:
    print("[ERR] cannot find python file containing run_file_allow endpoint")
    sys.exit(2)

score, target, s = cands[0]
print(f"[INFO] target={target} score={score}")

MARK = "VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1"
if MARK in s:
    print("[OK] contract marker already present; no change.")
    sys.exit(0)

ts = time.strftime("%Y%m%d_%H%M%S")
bak = target.with_name(target.name + f".bak_contract_{ts}")
bak.write_text(s, encoding="utf-8")
print(f"[BACKUP] {bak}")

# 2) inject contract set near top (after imports if possible)
contract_block = r'''
# ===================== VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1 =====================
# Dashboard minimal whitelist (exact paths; no glob)
_DASHBOARD_ALLOW_EXACT = {
  "run_gate_summary.json",
  "findings_unified.json",
  "run_gate.json",
  "run_manifest.json",
  "run_evidence_index.json",
  "reports/findings_unified.csv",
  "reports/findings_unified.sarif",
  "reports/findings_unified.html",
}
def _dash_allow_exact(path: str) -> bool:
  try:
    p = (path or "").strip().lstrip("/")
    if not p: return False
    if ".." in p or p.startswith(("/", "\\")): return False
    return p in _DASHBOARD_ALLOW_EXACT
  except Exception:
    return False
# ===================== /VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1 =====================
'''

# Place after last import block if found; else prepend
m = re.search(r"^(import\s.+|from\s.+import\s.+)\n(?:import\s.+\n|from\s.+import\s.+\n)*", s, flags=re.M)
if m:
    insert_at = m.end()
    s2 = s[:insert_at] + contract_block + "\n" + s[insert_at:]
else:
    s2 = contract_block + "\n" + s

# 3) patch allow-check patterns so dashboard-contract paths bypass "not allowed"
repls = 0

# pattern A: if not is_allowed_xxx(path): return not allowed
patA = re.compile(r"if\s+not\s+([a-zA-Z_][a-zA-Z0-9_]*)\(\s*path\s*\)\s*:\s*\n(\s+)(return\s+.*not allowed.*\n)", re.I)
def subA(m):
    global repls
    fn = m.group(1)
    indent = m.group(2)
    ret = m.group(3)
    repls += 1
    return f"if (not _dash_allow_exact(path)) and (not {fn}(path)):\n{indent}{ret}"
s3 = patA.sub(subA, s2, count=1)  # only touch first hit (endpoint scope)

# pattern B: if not allowed: return not allowed  (common inline)
patB = re.compile(r"\n(\s*)if\s+not\s+allowed\s*:\s*\n(\s+)(return\s+.*not allowed.*\n)", re.I)
def subB(m):
    global repls
    indent_if = m.group(1)
    indent_ret = m.group(2)
    ret = m.group(3)
    repls += 1
    return f"\n{indent_if}if (not allowed) and (not _dash_allow_exact(path)):\n{indent_ret}{ret}"
s4 = patB.sub(subB, s3, count=1)

# pattern C: function is_allowed_run_file... add fast-path at top
patC = re.compile(r"(def\s+([a-zA-Z_][a-zA-Z0-9_]*)\(\s*path\s*:\s*str\s*\)\s*->\s*bool\s*:\s*\n)", re.M)
mC = patC.search(s4)
if mC and ("allowed" in mC.group(2).lower() or "allow" in mC.group(2).lower()):
    head = mC.group(1)
    insert = head + "  if _dash_allow_exact(path):\n    return True\n"
    s4 = s4[:mC.start(1)] + insert + s4[mC.end(1):]
    repls += 1

if repls == 0:
    print("[WARN] did not find a known allow-check pattern. Contract block injected but allow bypass not wired.")
    print("[HINT] search manually in target for run_file_allow allowlist / not allowed branch.")
else:
    print(f"[OK] applied allow-bypass rewrites={repls}")

target.write_text(s4, encoding="utf-8")
print("[OK] wrote patch")
PY

echo "== py_compile =="
python3 -m py_compile /home/test/Data/SECURITY_BUNDLE/ui/*.py 2>/dev/null || true
python3 -m py_compile /home/test/Data/SECURITY_BUNDLE/ui/wsgi_vsp_ui_gateway.py

echo "== restart =="
systemctl restart "$SVC" || { echo "[ERR] restart failed: $SVC"; exit 2; }

echo "[DONE] run smoke again: bin/p0_dashboard_smoke_contract_v1.sh"
