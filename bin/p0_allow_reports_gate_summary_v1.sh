#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need sed

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_allow_reports_${TS}"
echo "[BACKUP] ${W}.bak_allow_reports_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

need_add = ["reports/run_gate_summary.json", "reports/run_gate.json"]
src = "".join(lines)
already = [x for x in need_add if x in src]
if len(already) == len(need_add):
    print("[OK] already has:", already)
    raise SystemExit(0)

# Find an anchor that is definitely in the live allow-list (from your 403 JSON)
anchor = "reports/findings_unified.tgz"
idx = None
for i, ln in enumerate(lines):
    if anchor in ln:
        idx = i
        break
if idx is None:
    raise SystemExit("[ERR] cannot find anchor in file: " + anchor)

# Scan upward to find start of the list/set literal
start = None
for j in range(idx, -1, -1):
    if ("ALLOW" in lines[j] or "allow" in lines[j]) and ("[" in lines[j] or "set([" in lines[j] or "({" in lines[j]):
        start = j
        break
# fallback: nearest line containing '[' before anchor
if start is None:
    for j in range(idx, -1, -1):
        if "[" in lines[j]:
            start = j
            break
if start is None:
    raise SystemExit("[ERR] cannot locate allow-list start")

# Scan downward to find end by bracket depth on '[' and ']'
depth = 0
end = None
for k in range(start, len(lines)):
    ln = lines[k]
    depth += ln.count("[")
    depth -= ln.count("]")
    if k == start and depth <= 0:
        # handle single-line list; keep scanning
        pass
    if k > start and depth <= 0:
        end = k
        break
if end is None:
    raise SystemExit("[ERR] cannot locate allow-list end")

block = "".join(lines[start:end+1])
# Decide quote style
quote = "'" if "'" in block else '"'

def ensure_item(block: str, item: str) -> str:
    if item in block:
        return block
    # Insert right after run_gate_summary.json if present (cleanest)
    key = "run_gate_summary.json"
    pos = block.find(key)
    if pos != -1:
        # find line end after that occurrence
        nl = block.find("\n", pos)
        if nl == -1:
            nl = len(block)
        insert = f"{quote}{item}{quote},\n"
        return block[:nl+1] + "  " + insert + block[nl+1:]
    # else insert before closing bracket
    close = block.rfind("]")
    if close == -1:
        return block
    insert = f"  {quote}{item}{quote},\n"
    return block[:close] + insert + block[close:]

new_block = block
for item in need_add:
    new_block = ensure_item(new_block, item)

if new_block == block:
    raise SystemExit("[ERR] failed to modify allow-list block")

# Replace the lines with new_block
new_lines = lines[:start] + [new_block] + lines[end+1:]
p.write_text("".join(new_lines), encoding="utf-8")
print("[OK] injected:", [x for x in need_add if x in new_block])
print("[OK] allow-list block lines:", start+1, "-", end+1)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.6
echo "[OK] restarted (or attempted)"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_RUN_20251219_092640}"

echo "== verify reports gate summary should be 200 =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | sed -n '1,15p'
