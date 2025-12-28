#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"
echo "[INFO] BASE=$BASE"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_runsv2_total_sort_${TS}"
echo "[BACKUP] ${W}.bak_runsv2_total_sort_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_RUNS_V2_TOTAL_SORT_P1_V3"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

# 1) append helper (cheap parse counts.TOTAL from head of findings_unified.json)
helper = r'''
# === {marker} ===
import os as __os
import re as __re

def __vsp_counts_total_from_json_head(__fp, __max_bytes=131072):
    """
    Fast-path: read first N bytes and regex counts.TOTAL.
    Avoid json.load() for huge findings_unified.json.
    Returns int (>=0).
    """
    if not __fp:
        return 0
    try:
        if not __os.path.isfile(__fp):
            return 0
        with open(__fp, "rb") as f:
            b = f.read(__max_bytes)
        # try "TOTAL": 123
        m = __re.search(rb'"TOTAL"\s*:\s*(\d+)', b)
        if m:
            return int(m.group(1))
        # fallback: "total": 123
        m = __re.search(rb'"total"\s*:\s*(\d+)', b)
        if m:
            return int(m.group(1))
        return 0
    except Exception:
        return 0
# === /{marker} ===
'''.replace("{marker}", marker)

s += ("\n" + helper + "\n")

# 2) patch runs_v2 handler: after items.append(...), compute findings_total & add into last item
# find function block containing /api/ui/runs_v2
lines = s.splitlines(True)

def find_line_idx(substr):
    for i, ln in enumerate(lines):
        if substr in ln:
            return i
    return -1

i_route = find_line_idx("/api/ui/runs_v2")
if i_route < 0:
    i_route = find_line_idx("'api/ui/runs_v2")
if i_route < 0:
    i_route = find_line_idx('"api/ui/runs_v2')
if i_route < 0:
    raise SystemExit("[ERR] cannot find /api/ui/runs_v2 in wsgi")

# find next def after decorator
i_def = -1
for j in range(i_route, min(i_route+40, len(lines))):
    if re.match(r'^\s*def\s+\w+\s*\(', lines[j]):
        i_def = j
        break
if i_def < 0:
    # sometimes decorator is on same line as route map; search further
    for j in range(i_route, min(i_route+120, len(lines))):
        if re.match(r'^\s*def\s+\w+\s*\(', lines[j]):
            i_def = j
            break
if i_def < 0:
    raise SystemExit("[ERR] cannot locate def handler for runs_v2")

indent = len(lines[i_def]) - len(lines[i_def].lstrip(" "))
# find end of function by indentation
i_end = len(lines)
for j in range(i_def+1, len(lines)):
    ln = lines[j]
    if not ln.strip():
        continue
    ind = len(ln) - len(ln.lstrip(" "))
    # next top-level def/decorator at same or less indent ends current def
    if ind <= indent and (ln.lstrip().startswith("def ") or ln.lstrip().startswith("@")):
        i_end = j
        break

block = lines[i_def:i_end]

# insert after items.append(...)
inserted_append = False
for k in range(len(block)):
    if "items.append" in block[k]:
        # determine indentation of this line
        indk = len(block[k]) - len(block[k].lstrip(" "))
        pad = " " * indk
        patch = (
            f"{pad}# {marker}: enrich last item with findings_total (cheap head-parse)\n"
            f"{pad}try:\n"
            f"{pad}    __it = items[-1] if items else None\n"
            f"{pad}    if __it is not None:\n"
            f"{pad}        __fp = __it.get('findings_path')\n"
            f"{pad}        __it['findings_total'] = int(__vsp_counts_total_from_json_head(__fp))\n"
            f"{pad}        # prefer 'has_findings' mean total>0 (keep file-exists semantics separately)\n"
            f"{pad}        __it['has_findings_nonzero'] = (__it.get('findings_total',0) > 0)\n"
            f"{pad}except Exception:\n"
            f"{pad}    pass\n"
        )
        block.insert(k+1, patch)
        inserted_append = True
        break

if not inserted_append:
    raise SystemExit("[ERR] cannot find items.append inside runs_v2 handler")

# insert sort right before return that returns items
inserted_sort = False
for k in range(len(block)-1, -1, -1):
    ln = block[k]
    if "return" in ln and "items" in ln and ("__wsgi_json" in ln or "json" in ln):
        indk = len(ln) - len(ln.lstrip(" "))
        pad = " " * indk
        sort_patch = (
            f"{pad}# {marker}: sort prefer nonzero findings_total desc, then mtime desc\n"
            f"{pad}try:\n"
            f"{pad}    items.sort(key=lambda x: (-(int(x.get('findings_total') or 0)), -(int(x.get('mtime') or 0))))\n"
            f"{pad}except Exception:\n"
            f"{pad}    pass\n"
        )
        block.insert(k, sort_patch)
        inserted_sort = True
        break

if not inserted_sort:
    raise SystemExit("[ERR] cannot locate return line with items in runs_v2 handler")

# write back
lines[i_def:i_end] = block
s2 = "".join(lines)
p.write_text(s2, encoding="utf-8")
print("[OK] patched:", marker)
PY

echo "== py_compile =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== restart (no sudo) =="
if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null || true
else
  echo "[WARN] missing bin/p1_ui_8910_single_owner_start_v2.sh; please restart UI manually."
fi

echo "== verify runs_v2 ordering (top should have biggest findings_total) =="
curl -fsS "$BASE/api/ui/runs_v2?limit=5" | python3 - <<'PY'
import json,sys
j=json.load(sys.stdin)
items=j.get("items",[])
print("top5:")
for it in items[:5]:
    print(it.get("rid"), "total=", it.get("findings_total"), "mtime=", it.get("mtime"), "overall=", it.get("overall"))
PY

echo "== sanity: pick known nonzero RID and ensure findings_v2 total>0 =="
curl -fsS "$BASE/api/ui/findings_v2?rid=RUN_20251120_130310&limit=1&offset=0" | python3 - <<'PY'
import json,sys
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "rid=", j.get("rid"), "total=", j.get("total"), "overall=", j.get("overall"))
PY

echo "[DONE] runs_v2 now prefers nonzero findings_total. Hard-refresh browser (Ctrl+Shift+R)."
