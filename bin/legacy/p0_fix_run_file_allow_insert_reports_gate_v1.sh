#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_runfileallow_reports_gate_${TS}"
echo "[BACKUP] ${W}.bak_runfileallow_reports_gate_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# locate the first route that mentions "/api/vsp/run_file_allow"
m = re.search(r'@.*?\(\s*[\'"]\/api\/vsp\/run_file_allow[\'"].*?\)\s*\n\s*def\s+([A-Za-z0-9_]+)\s*\(', s, flags=re.S)
if not m:
    raise SystemExit("[ERR] cannot find /api/vsp/run_file_allow route")

fn = m.group(1)
start = m.start()

# take a window after the handler to find allowlist assignment
win = s[start:start+8000]

# find allow list inside that window: allow = [ ... ]
m2 = re.search(r'(\ballow\s*=\s*\[)(.*?)(\]\s*)', win, flags=re.S)
if not m2:
    raise SystemExit("[ERR] cannot find allow=[...] near run_file_allow handler")

head, body, tail = m2.group(1), m2.group(2), m2.group(3)

need_items = [
  "reports/run_gate_summary.json",
  "reports/run_gate.json",
]
changed = 0
for item in need_items:
    if item not in body:
        # insert right after run_gate_summary.json if present, else append at end
        if "run_gate_summary.json" in body:
            body = re.sub(r'("run_gate_summary\.json"\s*,?)', r'\1 "'+item+'",', body, count=1)
        else:
            body = body.rstrip() + f'\n    "{item}",\n'
        changed += 1

win2 = win[:m2.start(1)] + head + body + tail + win[m2.end(3):]
s2 = s[:start] + win2 + s[start+len(win):]

if s2 == s:
    print("[OK] no change (already present)")
else:
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] inserted into allowlist near handler {fn}: add={changed}")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

RID="$(curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print(j.get("latest_rid",""))
PY
)"
echo "[RID]=$RID"
echo "-- run_file_allow reports/run_gate_summary.json --"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 30

echo "[DONE] Hard reload /runs (Ctrl+Shift+R)."
