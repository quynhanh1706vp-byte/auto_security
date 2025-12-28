#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] not found: $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_runs_fs_${TS}"
echo "[BACKUP] $F.bak_runs_fs_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace")

if "RUNS_INDEX_FS_V1" in txt:
    print("[SKIP] endpoint already added")
    raise SystemExit(0)

block = r'''
# === RUNS_INDEX_FS_V1 ===
import os, json, time
from flask import request, jsonify

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
    # fast FS listing to avoid proxy timeouts / empty response
    limit = request.args.get("limit", "40")
    try:
        limit_i = max(1, min(500, int(limit)))
    except Exception:
        limit_i = 40
    root = Path(__file__).resolve().parents[1]  # .../ui
    bundle_root = root.parent                  # .../SECURITY_BUNDLE
    out_dir = bundle_root / "out"
    items = _pick_runs_fs(str(out_dir), limit_i)
    kpi = {
        "total_runs": len(items),
        "last_n": min(20, len(items)),
    }
    return jsonify({"ok": True, "source": "fs", "items": items, "kpi": kpi})
# === END RUNS_INDEX_FS_V1 ===
'''

# chèn block ngay sau imports đầu file (sau dòng "from flask ..." nếu có)
m = re.search(r'(?m)^from flask[^\n]*\n', txt)
if m:
    ins = m.end()
    txt = txt[:ins] + block + "\n" + txt[ins:]
else:
    txt = block + "\n" + txt

p.write_text(txt, encoding="utf-8")
print("[OK] added /api/vsp/runs_index_v3_fs (FS fast)")
PY

bash -n "$F" && echo "[OK] syntax ok"
