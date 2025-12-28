#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] not found: $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_runsfs_enrich_${TS}"
echo "[BACKUP] $F.bak_runsfs_enrich_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

m = re.search(r'(?s)# === RUNS_INDEX_FS_V1 ===.*?# === END RUNS_INDEX_FS_V1 ===', txt)
if not m:
    raise SystemExit("[ERR] RUNS_INDEX_FS_V1 block not found")

blk = m.group(0)

# 1) Add helper to compute findings sum
if "def _runsfs_sum_totals" not in blk:
    blk = blk.replace(
        "def _runsfs_pick_runs(out_root, limit=50):",
        "def _runsfs_sum_totals(totals):\n"
        "    if not isinstance(totals, dict):\n"
        "        return 0\n"
        "    s = 0\n"
        "    for k,v in totals.items():\n"
        "        try:\n"
        "            s += int(v)\n"
        "        except Exception:\n"
        "            pass\n"
        "    return s\n\n"
        "def _runsfs_pick_runs(out_root, limit=50, hide_empty=False):"
    )

# 2) When appending item, compute has_findings
# Find the items.append({...}) block and add has_findings + sum
blk = re.sub(
    r'items\.append\(\{\s*"run_id":\s*name,([\s\S]*?)"totals":\s*bysev if isinstance\(bysev, dict\) else \{\},\s*\}\)',
    lambda mm: mm.group(0).replace(
        '"totals": bysev if isinstance(bysev, dict) else {},',
        '"totals": bysev if isinstance(bysev, dict) else {},\n'
        '                "total_findings": _runsfs_sum_totals(bysev if isinstance(bysev, dict) else {}),\n'
        '                "has_findings": 1 if _runsfs_sum_totals(bysev if isinstance(bysev, dict) else {}) > 0 else 0,'
    ),
    blk
)

# 3) Allow hide_empty query param + hide_empty logic
blk = blk.replace(
    "items = _runsfs_pick_runs(str(out_dir), limit_i)",
    "hide_empty = request.args.get('hide_empty','0') in ('1','true','yes')\n"
    "    items = _runsfs_pick_runs(str(out_dir), limit_i, hide_empty=hide_empty)"
)

# 4) Implement hide_empty filtering + prefer has_findings sorting
if "hide_empty" in blk and "prefer has_findings" not in blk:
    blk = blk.replace(
        "items.sort(key=lambda x: x.get(\"created_at\",\"\"), reverse=True)",
        "if hide_empty:\n"
        "        items = [it for it in items if int(it.get('has_findings',0)) == 1]\n"
        "    # prefer has_findings then by time\n"
        "    items.sort(key=lambda x: (int(x.get('has_findings',0)), x.get('created_at','')), reverse=True)\n"
        "    # prefer has_findings sorting"
    )

txt2 = txt[:m.start()] + blk + txt[m.end():]
p.write_text(txt2, encoding="utf-8")
print("[OK] runs_index_v3_fs enriched: has_findings + hide_empty + sort preference")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] python syntax OK"

pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "=== FS runs (hide_empty=1) ==="
curl -s "http://localhost:8910/api/vsp/runs_index_v3_fs?limit=10&hide_empty=1" | head -c 600; echo
