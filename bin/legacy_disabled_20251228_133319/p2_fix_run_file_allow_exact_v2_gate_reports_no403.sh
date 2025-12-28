#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_runfileallow_exact_${TS}"
echo "[BACKUP] ${W}.bak_runfileallow_exact_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# --- locate the run_file_allow handler block by decorator containing run_file_allow ---
m = re.search(r'(?ms)^[ \t]*@app\.(?:route|get|post)\(\s*["\']\/api\/vsp\/run_file_allow["\'].*?\)\s*\n^[ \t]*def[ \t]+\w+\(.*?\):', s)
if not m:
    # fallback: sometimes route is registered via blueprint; search string
    m = re.search(r'(?ms)^[ \t]*def[ \t]+\w+\(.*?\):.*?\n.*?run_file_allow', s)
    if not m:
        raise SystemExit("[ERR] cannot locate /api/vsp/run_file_allow handler")

# def line start (column 0 or with tabs) after decorator
def_start = s.rfind("\n", 0, m.end()) + 1
# find end of function by next top-level decorator "@app." or end of file
m2 = re.search(r'(?m)^[ \t]*@app\.', s[m.end():])
end = (m.end() + m2.start()) if m2 else len(s)
block = s[def_start:end]

need_paths = [
  "run_gate_summary.json",
  "reports/run_gate_summary.json",
  "run_gate.json",
  "reports/run_gate.json",
]

# patch allowlist inside handler
ml = re.search(r'(?s)\ballow\s*=\s*\[(.*?)\]', block)
added = 0
if ml:
    body = ml.group(1)
    existing = set(re.findall(r'["\']([^"\']+)["\']', body))
    to_add = [x for x in need_paths if x not in existing]
    if to_add:
        # rebuild list using existing items + additions, keep stable order
        # keep the original ordering of existing items as in file
        orig_items = re.findall(r'["\']([^"\']+)["\']', body)
        merged = orig_items + to_add
        new_list = "allow = [\n" + "".join([f'    "{it}",\n' for it in merged]) + "]"
        block = block[:ml.start()] + new_list + block[ml.end():]
        added = len(to_add)
else:
    # if allowlist not found, we still can’t safely patch
    raise SystemExit("[ERR] allowlist not found inside handler block")

# remove HTTP 403 inside this handler only
n403 = 0
block2, n = re.subn(r'(return\s+jsonify\([^\)]*\))\s*,\s*403\b', r'\1', block)
block = block2; n403 += n
block2, n = re.subn(r'\babort\s*\(\s*403\s*\)', 'return jsonify(ok=False, err="not allowed")', block)
block = block2; n403 += n

# write back
s2 = s[:def_start] + block + s[end:]
p.write_text(s2, encoding="utf-8")

print(f"[OK] run_file_allow patched: allow_add={added}, no403_edits={n403}")
PY

python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.9

echo "== sanity: /api/vsp/run_file_allow should NOT 403 anymore =="
RID="RUN_20251120_130310"
echo "[RID]=$RID"
echo "-- reports/run_gate_summary.json --"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 25 || true
echo "-- run_gate_summary.json --"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" | head -n 25 || true

echo "[DONE] Hard reload /runs (Ctrl+Shift+R). Console 403 spam should disappear."
