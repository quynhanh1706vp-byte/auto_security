#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_sig_gate_${TS}"
echo "[BACKUP] ${W}.bak_sig_gate_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

# signature tokens that appear in the 403 response allowlist
sig = [
  '"SUMMARY.txt"',
  '"findings_unified.json"',
  '"reports/findings_unified.tgz"',
  '"run_gate_summary.json"',
]

# find candidate windows containing all signature tokens
cands = []
for i,l in enumerate(lines):
    if '"SUMMARY.txt"' not in l:
        continue
    w0 = max(0, i-80)
    w1 = min(len(lines), i+120)
    w = "".join(lines[w0:w1])
    if all(t in w for t in sig) and "reports/run_gate_summary.json" not in w:
        cands.append((i,w0,w1))

if not cands:
    print("[ERR] cannot find matching allowlist window by signature (or already contains reports/run_gate_summary.json)")
    raise SystemExit(2)

# pick candidate closest to /api/vsp/run_file_allow occurrence
route_idxs = [i for i,l in enumerate(lines) if "/api/vsp/run_file_allow" in l]
def dist(c):
    if not route_idxs: return 10**9
    return min(abs(c[0]-r) for r in route_idxs)

cands.sort(key=dist)
i, w0, w1 = cands[0]

# insert after the line containing "run_gate_summary.json",
inserted = 0
for j in range(w0, w1):
    if re.search(r'^\s*["\']run_gate_summary\.json["\']\s*,\s*$', lines[j]):
        indent = re.match(r'^(\s*)', lines[j]).group(1)
        lines.insert(j+1, f'{indent}"reports/run_gate_summary.json",\n')
        inserted = 1
        break

if not inserted:
    print("[ERR] signature window found but cannot locate exact list item line 'run_gate_summary.json',")
    raise SystemExit(3)

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] inserted reports/run_gate_summary.json near line {i+1} (window {w0+1}-{w1})")
PY

echo "== py_compile =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" || true
sleep 0.9

echo "== sanity: read RID safely =="
curl -sS -D- -o /tmp/_runs.json "$BASE/api/vsp/runs?limit=1" | sed -n '1,12p'
head -c 120 /tmp/_runs.json; echo

RID="$(python3 - <<'PY'
import json
j=json.load(open("/tmp/_runs.json","r",encoding="utf-8"))
print(j["items"][0]["run_id"])
PY
)"
echo "[RID]=$RID"

echo "== sanity: run_file_allow reports/run_gate_summary.json (must NOT be 403 not allowed) =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 60

echo "[DONE] Hard reload /runs (Ctrl+Shift+R)."
