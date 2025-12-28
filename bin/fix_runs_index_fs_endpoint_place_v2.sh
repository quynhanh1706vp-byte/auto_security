#!/usr/bin/env bash
set -euo pipefail

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] not found: $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_fix_runsfs_${TS}"
echo "[BACKUP] $F.bak_fix_runsfs_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

# 1) Extract block (if exists)
m = re.search(r'(?s)# === RUNS_INDEX_FS_V1 ===.*?# === END RUNS_INDEX_FS_V1 ===\n?', txt)
block = None
if m:
    block = m.group(0)
    txt = txt[:m.start()] + txt[m.end():]
else:
    # If not found, re-create block (safe)
    block = r'''# === RUNS_INDEX_FS_V1 ===
import os, json, time
from flask import request, jsonify
from pathlib import Path

def _safe_load_json(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return json.load(f)
    except Exception:
        return None

def _pick_runs_fs(root_out, limit=50):
    items = []
    try:
        for name in os.listdir(root_out):
            if not name.startswith("RUN_"):
                continue
            run_dir = os.path.join(root_out, name)
            if not os.path.isdir(run_dir):
                continue
            rpt = os.path.join(run_dir, "report")
            summary = os.path.join(rpt, "summary_unified.json")
            st = os.stat(run_dir)
            created_at = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(st.st_mtime))
            meta = _safe_load_json(os.path.join(run_dir, "ci_source_meta.json")) or {}
            s = _safe_load_json(summary) or {}
            bysev = (s.get("summary_by_severity") or s.get("by_severity") or {})
            items.append({
                "run_id": name,
                "created_at": created_at,
                "profile": (meta.get("profile") or s.get("profile") or ""),
                "target": (meta.get("target") or s.get("target") or ""),
                "totals": bysev if isinstance(bysev, dict) else {},
            })
    except Exception:
        pass
    items.sort(key=lambda x: x.get("created_at",""), reverse=True)
    return items[:max(1,int(limit))]

@app.get("/api/vsp/runs_index_v3_fs")
def vsp_runs_index_v3_fs():
    limit = request.args.get("limit", "40")
    try:
        limit_i = max(1, min(500, int(limit)))
    except Exception:
        limit_i = 40
    root = Path(__file__).resolve().parents[1]  # .../ui
    bundle_root = root.parent                  # .../SECURITY_BUNDLE
    out_dir = bundle_root / "out"
    items = _pick_runs_fs(str(out_dir), limit_i)
    kpi = {"total_runs": len(items), "last_n": min(20, len(items))}
    return jsonify({"ok": True, "source": "fs", "items": items, "kpi": kpi})
# === END RUNS_INDEX_FS_V1 ===
'''

# 2) Ensure import Path exists somewhere (safe, even if duplicate)
if "from pathlib import Path" not in txt:
    # insert near top after first import line
    m2 = re.search(r'(?m)^import .+\n', txt)
    if m2:
        ins = m2.end()
        txt = txt[:ins] + "from pathlib import Path\n" + txt[ins:]
    else:
        txt = "from pathlib import Path\n" + txt

# 3) Insert block AFTER app = Flask(...)
m3 = re.search(r'(?m)^\s*app\s*=\s*Flask\([^)]*\)\s*$', txt)
if not m3:
    # try "Flask(__name__)" with spaces, or app=flask.Flask
    m3 = re.search(r'(?m)^\s*app\s*=\s*.*Flask\([^)]*\)\s*$', txt)

if not m3:
    # fallback: append near end (won't work if app created later in if __name__ block)
    txt = txt + "\n\n" + block + "\n"
    where = "EOF (fallback)"
else:
    ins = m3.end()
    txt = txt[:ins] + "\n\n" + block + "\n" + txt[ins:]
    where = f"after app=Flask at line ~{txt[:ins].count(chr(10))+1}"

p.write_text(txt, encoding="utf-8")
print("[OK] RUNS_INDEX_FS_V1 placed", where)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] python syntax clean"

# quick grep to show placement context
grep -n "app *= *Flask" -n vsp_demo_app.py | head -n 3 || true
grep -n "RUNS_INDEX_FS_V1" -n vsp_demo_app.py | head -n 3 || true
