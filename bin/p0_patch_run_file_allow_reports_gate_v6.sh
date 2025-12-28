#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_runfileallow_v6_${TS}"
echo "[BACKUP] ${W}.bak_runfileallow_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RUN_FILE_ALLOW_REPORTS_GATE_V6"
if MARK in s:
    print("[OK] marker already present; skip")
    sys.exit(0)

needle = "/api/vsp/run_file_allow"
pos = s.find(needle)
if pos < 0:
    raise SystemExit("[ERR] cannot find /api/vsp/run_file_allow string in wsgi")

# take a window after the route to find the handler block
win = s[pos:pos+12000]

# find first 'def ...' after the route declaration
mdef = re.search(r'\n\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', win)
if not mdef:
    raise SystemExit("[ERR] cannot locate handler def after run_file_allow route")

def_start = pos + mdef.start()

# handler end heuristic: next "\n@" at col 0-ish or "\ndef " at col 0-ish after def_start
tail = s[def_start:def_start+20000]
mend = re.search(r'\n@|\n(?=def\s)', tail[1:])  # next decorator/def
end_i = def_start + (mend.start()+1 if mend else len(tail))

block = s[def_start:end_i]

# locate allow-check:  if rel not in ALLOW:
mchk = re.search(r'\n(\s*)if\s+rel\s+not\s+in\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*\n', block)
if not mchk:
    # sometimes uses "if rel not in allow:"
    mchk = re.search(r'\n(\s*)if\s+rel\s+not\s+in\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*$', block, re.M)
if not mchk:
    # fall back: any "not in" line mentioning rel
    mchk = re.search(r'\n(\s*)if\s+.*rel.*not\s+in\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*\n', block)
if not mchk:
    raise SystemExit("[ERR] cannot find allow-check line `if rel not in <ALLOW>:` inside handler block")

indent = mchk.group(1)
allowvar = mchk.group(2)

orig_line_span = (mchk.start(), mchk.end())
orig = block[mchk.start():mchk.end()]

inject = (
f"\n{indent}# ===================== {MARK} =====================\n"
f"{indent}# allow ONLY reports/run_gate*.json by checking base-name in allowlist\n"
f"{indent}rel_check = rel\n"
f"{indent}if rel in ('reports/run_gate_summary.json','reports/run_gate.json'):\n"
f"{indent}    try:\n"
f"{indent}        rel_check = rel.split('/',1)[1]\n"
f"{indent}    except Exception:\n"
f"{indent}        rel_check = rel\n"
f"{indent}if rel_check not in {allowvar}:\n"
)

# replace the original `if rel not in ALLOW:` line with our rel_check version
block2 = block[:mchk.start()] + inject + block[mchk.end():]

s2 = s[:def_start] + block2 + s[end_i:]
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched handler allow-check: allowvar={allowvar} (route contains {needle})")
PY

echo "== compile check =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

echo "== sanity =="
RID="RUN_20251120_130310"
echo "-- run_file_allow (reports gate summary) --"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 60
echo
echo "-- run_file_allow (root gate summary) --"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" | head -n 40
