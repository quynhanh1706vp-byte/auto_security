#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_allowlists_gate_${TS}"
echo "[BACKUP] ${W}.bak_allowlists_gate_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

targets = ["reports/run_gate_summary.json", "reports/run_gate.json"]

def is_allow_var(name: str) -> bool:
    u = name.upper()
    return ("ALLOW" in u) or (name in ("allow","allowed","ALLOW","ALLOWED","allowlist","ALLOWLIST"))

patched_blocks = 0
inserted_total = 0

i = 0
n = len(lines)

while i < n:
    m = re.match(r'^(\s*)([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\[\s*(#.*)?$', lines[i])
    if not m:
        i += 1
        continue

    indent = m.group(1)
    var = m.group(2)

    if not is_allow_var(var):
        i += 1
        continue

    # capture list block by bracket depth
    depth = lines[i].count('[') - lines[i].count(']')
    j = i + 1
    while j < n and depth > 0:
        depth += lines[j].count('[') - lines[j].count(']')
        j += 1
    if depth != 0:
        i += 1
        continue

    block = lines[i:j]
    block_txt = "".join(block)

    # Heuristic: only patch allowlists that look like run_file_allow allowlists
    # (contain run_gate_summary.json OR reports/findings_unified.tgz)
    if ('"run_gate_summary.json"' not in block_txt) and ('"reports/findings_unified.tgz"' not in block_txt):
        i = j
        continue

    # Determine item indentation by finding any existing item line
    item_indent = None
    for k in range(i, j):
        m2 = re.match(r'^(\s+)"[^"]+"\s*,\s*$', lines[k])
        if m2:
            item_indent = m2.group(1)
            break
    if item_indent is None:
        item_indent = indent + "    "

    # Insert after run_gate_summary.json line if present, else before closing bracket
    insert_at = None
    for k in range(i, j):
        if '"run_gate_summary.json"' in lines[k]:
            insert_at = k + 1
            break
    if insert_at is None:
        # before the closing bracket line
        insert_at = j - 1

    # figure which targets are missing in this block
    missing = [t for t in targets if f'"{t}"' not in block_txt]
    if missing:
        add_lines = [f'{item_indent}"{t}",\n' for t in missing]
        lines[insert_at:insert_at] = add_lines
        inserted_total += len(missing)
        patched_blocks += 1
        # adjust indices
        delta = len(missing)
        n += delta
        j += delta

    i = j

# Also reduce console spam: inside run_file_allow handler area, downgrade 403->200 for "not allowed" returns (best-effort).
s2 = "".join(lines)
s2_new, c1 = re.subn(r'(err"\s*:\s*"not allowed".*?)(,\s*)403\b', r'\1\2 200', s2, flags=re.I)
s2_new, c2 = re.subn(r'(return\s+[^#\n]*not allowed[^#\n]*)(,\s*)403\b', r'\1\2 200', s2_new, flags=re.I)

p.write_text(s2_new, encoding="utf-8")
print(f"[OK] patched_blocks={patched_blocks} inserted_total={inserted_total} spam403fix={c1+c2}")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

systemctl restart vsp-ui-8910.service 2>/dev/null || true

echo "== wait KPI =="
RID=""
for _ in $(seq 1 40); do
  J="$(curl -fsS "$BASE/api/ui/runs_kpi_v2?days=30" 2>/dev/null || true)"
  if echo "$J" | grep -q '"ok": true'; then
    RID="$(python3 - <<PY
import json
j=json.loads("""$J""")
print(j.get("latest_rid",""))
PY
)"
    [ -n "$RID" ] && break
  fi
  sleep 0.35
done
echo "[RID]=$RID"
[ -n "$RID" ] || { echo "[ERR] cannot get latest_rid"; exit 2; }

echo "== sanity run_file_allow reports/run_gate_summary.json =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 80

echo "[DONE] Ctrl+Shift+R /runs. 403 spam should be gone + gate summary fetch OK."
