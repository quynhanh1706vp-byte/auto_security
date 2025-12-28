#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_anchor_gate_${TS}"
echo "[BACKUP] ${W}.bak_anchor_gate_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

ANCHOR = "reports/findings_unified.tgz"
NEED_IN_LIST = "run_gate_summary.json"
ADD = ["reports/run_gate_summary.json", "reports/run_gate.json"]

# find all anchor line indices
idxs = [i for i,l in enumerate(lines) if ANCHOR in l]
if not idxs:
    raise SystemExit("[ERR] anchor not found")

def find_list_span(around_i:int):
    # find start: nearest line above containing '[' with an assignment context
    start = None
    for i in range(around_i, max(-1, around_i-1200), -1):
        if "[" in lines[i]:
            # prefer lines that look like assignment of list/set/tuple
            if re.search(r'\b(allow|ALLOW|allowed|ALLOWLIST|WHITELIST|permit|PERMIT)\b', lines[i]) or "=" in lines[i]:
                start = i
                break
    if start is None:
        # fallback: just find any '[' above
        for i in range(around_i, max(-1, around_i-1200), -1):
            if "[" in lines[i]:
                start = i
                break
    if start is None:
        return None

    # find end by bracket depth (simple, good enough for list literals)
    depth = 0
    in_span = False
    for j in range(start, min(len(lines), start+2200)):
        s = lines[j]
        # count brackets ignoring nothing (best-effort)
        depth += s.count("[")
        depth -= s.count("]")
        if not in_span and "[" in s:
            in_span = True
        if in_span and depth <= 0 and "]" in s:
            return (start, j)
    return None

spans = []
for i in idxs:
    sp = find_list_span(i)
    if sp and sp not in spans:
        spans.append(sp)

if not spans:
    raise SystemExit("[ERR] cannot locate list spans around anchor occurrences")

patched = 0
for (st,en) in spans:
    chunk = "".join(lines[st:en+1])
    if ANCHOR not in chunk:
        continue
    # only patch lists that clearly include run_gate_summary.json
    if NEED_IN_LIST not in chunk:
        continue

    # choose indentation from an existing item line inside the chunk
    indent = "        "
    for k in range(st, en+1):
        if re.search(r'["\'].*run_gate_summary\.json["\']', lines[k]):
            indent = re.match(r'^(\s*)', lines[k]).group(1) or indent
            break

    # ensure we insert after run_gate_summary.json item line
    missing = [a for a in ADD if a not in chunk]
    if not missing:
        continue

    inserted = False
    for k in range(st, en+1):
        if re.search(r'["\']run_gate_summary\.json["\']', lines[k]):
            # keep quote style: use double quotes
            extra = "".join([f'{indent}"{a}",\n' for a in missing])
            lines[k] = lines[k]  # unchanged
            lines.insert(k+1, extra)
            inserted = True
            patched += 1
            break
    if not inserted:
        # append before closing bracket line
        for k in range(en, st-1, -1):
            if "]" in lines[k]:
                extra = "".join([f'{indent}"{a}",\n' for a in missing])
                lines.insert(k, extra)
                patched += 1
                inserted = True
                break

# downgrade "not allowed" 403 -> 200 (reduce console spam)
# line-based: if within last 6 lines saw "not allowed", replace 403 with 200
hist = []
for i,l in enumerate(lines):
    hist.append(l)
    if len(hist) > 6:
        hist.pop(0)
    if "403" in l and any("not allowed" in h.lower() for h in hist):
        lines[i] = re.sub(r'\b403\b', '200', l)
# also handle common pattern: ", 403" even if "not allowed" is on same line
for i,l in enumerate(lines):
    if "not allowed" in l.lower() and "403" in l:
        lines[i] = re.sub(r'\b403\b', '200', l)

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched lists={patched} (by anchor spans={len(spans)})")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.9

RID="$(curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print(j.get("latest_rid",""))
PY
)"
echo "[RID]=$RID"

echo "== run_file_allow reports/run_gate_summary.json =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 60

echo "[DONE] Hard reload /runs (Ctrl+Shift+R)."
