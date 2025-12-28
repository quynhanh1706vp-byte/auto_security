#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_strip_reports_gate_v2_${TS}"
echo "[BACKUP] ${W}.bak_strip_reports_gate_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

MARK = "VSP_P0_STRIP_REPORTS_GATE_IN_RUN_FILE_ALLOW_V2"
if any(MARK in ln for ln in lines):
    print("[OK] marker already present, skip")
    sys.exit(0)

# 1) find the route mention for run_file_allow
route_i = None
for i, ln in enumerate(lines):
    if "/api/vsp/run_file_allow" in ln:
        route_i = i
        break
if route_i is None:
    print("[ERR] cannot find /api/vsp/run_file_allow")
    sys.exit(2)

# 2) find next def/async def after route
def_i = None
indent_def = None
for j in range(route_i, min(route_i + 300, len(lines))):
    m = re.match(r'^(\s*)(async\s+def|def)\s+[A-Za-z0-9_]+\s*\(', lines[j])
    if m:
        def_i = j
        indent_def = m.group(1)
        break
if def_i is None:
    print("[ERR] cannot find def() after run_file_allow route (within 300 lines)")
    sys.exit(2)

def_indent_len = len(indent_def)

# 3) find end of function block by indentation
end_i = len(lines)
for k in range(def_i + 1, len(lines)):
    ln = lines[k]
    if ln.strip() == "" or ln.lstrip().startswith("#"):
        continue
    # decorator at top-level is allowed to end block too; treat as end if indent < def indent
    cur_indent = len(re.match(r'^(\s*)', ln).group(1))
    if cur_indent < def_indent_len and not ln.lstrip().startswith("@"):
        end_i = k
        break

block = lines[def_i:end_i]

# 4) find first assignment to rel/path inside function
assign_idx = None
for idx, ln in enumerate(block):
    if re.match(r'^\s*(rel|relpath|path)\s*=\s*', ln):
        assign_idx = idx
        break
if assign_idx is None:
    print("[ERR] cannot find rel/path assignment inside run_file_allow handler")
    sys.exit(2)

assign_indent = re.match(r'^(\s*)', block[assign_idx]).group(1)

snippet = [
    f"{assign_indent}# {MARK}\n",
    f"{assign_indent}# normalize: accept reports/run_gate*.json via existing basename allowlist\n",
    f"{assign_indent}try:\n",
    f"{assign_indent}    _r = (rel or '').lstrip('/').replace('\\\\','/')\n",
    f"{assign_indent}except Exception:\n",
    f"{assign_indent}    _r = ''\n",
    f"{assign_indent}if _r in ('reports/run_gate_summary.json','reports/run_gate.json'):\n",
    f"{assign_indent}    rel = _r.split('/',1)[1]\n",
]

# insert right after the assignment line
block2 = block[:assign_idx+1] + snippet + block[assign_idx+1:]
lines2 = lines[:def_i] + block2 + lines[end_i:]

p.write_text("".join(lines2), encoding="utf-8")
print("[OK] inserted strip-reports normalize into run_file_allow handler")
print(f"[OK] patched function lines: def_i={def_i+1}, end_i={end_i}")
PY

python3 -m py_compile "$W" && echo "[OK] py_compile OK"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print(j["items"][0]["run_id"])
PY
)"
echo "[RID]=$RID"

echo "== sanity run_file_allow reports/run_gate_summary.json =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 60
