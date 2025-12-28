#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_strip_reports_gate_${TS}"
echo "[BACKUP] ${W}.bak_strip_reports_gate_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_STRIP_REPORTS_GATE_IN_RUN_FILE_ALLOW_V1"
if MARK in s:
    print("[OK] marker already present, skip patch")
    raise SystemExit(0)

# find the /api/vsp/run_file_allow handler block
m = re.search(r'(/api/vsp/run_file_allow)', s)
if not m:
    raise SystemExit("[ERR] cannot find /api/vsp/run_file_allow in wsgi")

# search forward for the nearest "def ..." after the route
tail = s[m.start():]
mdef = re.search(r'\n\s*def\s+[A-Za-z0-9_]+\s*\(', tail)
if not mdef:
    raise SystemExit("[ERR] cannot find def() after run_file_allow route")

def_pos = m.start() + mdef.start()

# determine function indentation
line_start = s.rfind("\n", 0, def_pos) + 1
def_line = s[line_start:s.find("\n", line_start)]
indent = re.match(r'(\s*)def\s', def_line).group(1)

# slice the function block by indentation
lines = s.splitlines(True)
# compute line index of def
cur = 0
def_li = None
for i,ln in enumerate(lines):
    cur += len(ln)
    if cur > def_pos:
        def_li = i
        break
if def_li is None:
    raise SystemExit("[ERR] internal: cannot map def line index")

# collect function block until next non-blank/non-comment with indent < def indent (or EOF)
def_indent_len = len(indent)
end_li = len(lines)
for j in range(def_li+1, len(lines)):
    ln = lines[j]
    if ln.strip()=="":
        continue
    if ln.lstrip().startswith("#"):
        continue
    cur_indent = len(re.match(r'(\s*)', ln).group(1))
    if cur_indent < def_indent_len and not ln.lstrip().startswith("@"):
        end_li = j
        break

block = "".join(lines[def_li:end_li])

# find a rel/path assignment inside this function block
# prefer "rel =" then "path =" then "relpath ="
mrel = re.search(r'^\s*(rel|relpath|path)\s*=\s*.*$', block, flags=re.M)
if not mrel:
    raise SystemExit("[ERR] cannot find rel/path assignment inside run_file_allow handler")

# insert right after that assignment line
ins_at = mrel.end()
# detect indentation of that assignment line
assign_line = mrel.group(0)
assign_indent = re.match(r'(\s*)', assign_line).group(1)

snippet = (
    f"\n{assign_indent}# {MARK}\n"
    f"{assign_indent}# normalize: allow reports/run_gate*.json via existing basename allowlist\n"
    f"{assign_indent}try:\n"
    f"{assign_indent}    _r = (rel or '').lstrip('/').replace('\\\\\\\', '/').replace('\\\\', '/')\n"
    f"{assign_indent}except Exception:\n"
    f"{assign_indent}    _r = ''\n"
    f"{assign_indent}if _r in ('reports/run_gate_summary.json','reports/run_gate.json'):\n"
    f"{assign_indent}    rel = _r.split('/',1)[1]\n"
)

block2 = block[:ins_at] + snippet + block[ins_at:]

s2 = "".join(lines[:def_li]) + block2 + "".join(lines[end_li:])
p.write_text(s2, encoding="utf-8")
print("[OK] patched run_file_allow to strip reports/ for gate files")
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
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 40
