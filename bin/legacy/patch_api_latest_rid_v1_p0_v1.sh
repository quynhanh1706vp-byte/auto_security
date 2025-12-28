#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "$APP.bak_latest_rid_${TS}"
echo "[BACKUP] $APP.bak_latest_rid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="replace")

# if already exists
if "/api/vsp/latest_rid_v1" in s:
  print("[OK] latest_rid_v1 route already present (skip)")
  raise SystemExit(0)

# ensure imports
need_imports = ["import json", "from pathlib import Path"]
for imp in need_imports:
  if imp not in s:
    # insert after first imports block
    s = re.sub(r'(?m)^(import\s+[^\n]+\n)+', lambda m: m.group(0) + imp + "\n", s, count=1)

route_code = r'''
# --- API: latest RID (commercial P0) ---
@app.get("/api/vsp/latest_rid_v1")
def api_vsp_latest_rid_v1():
    """
    Return latest RID for UI auto-pick when hash route changes.
    Best-effort: read runs index under ui/out_ci or scan SECURITY_BUNDLE/out.
    """
    try:
        base = Path(__file__).resolve().parent
        out_ci = base / "out_ci"

        # 1) prefer explicit runs index if present
        candidates = [
            out_ci / "runs_index_v3.json",
            out_ci / "runs_index_v2.json",
            out_ci / "runs_index.json",
            out_ci / "runs_history.json",
            out_ci / "vsp_runs_history.json",
            out_ci / "latest_run.json",
        ]
        for p in candidates:
            if p.exists() and p.stat().st_size > 0:
                try:
                    j = json.loads(p.read_text(encoding="utf-8", errors="replace"))
                except Exception:
                    continue
                # common shapes
                rid = None
                if isinstance(j, dict):
                    rid = j.get("rid") or j.get("latest_rid") or j.get("run_id")
                    if not rid and isinstance(j.get("runs"), list) and j["runs"]:
                        x = j["runs"][0]
                        if isinstance(x, str):
                            rid = x
                        elif isinstance(x, dict):
                            rid = x.get("rid") or x.get("run_id") or x.get("id")
                elif isinstance(j, list) and j:
                    x = j[0]
                    if isinstance(x, str):
                        rid = x
                    elif isinstance(x, dict):
                        rid = x.get("rid") or x.get("run_id") or x.get("id")
                if rid:
                    return {"ok": True, "rid": str(rid), "source": p.name}

        # 2) fallback: scan SECURITY_BUNDLE/out for newest RUN_* dir, try read run_id inside
        root = base.parent  # /home/test/Data/SECURITY_BUNDLE
        out_root = root / "out"
        if out_root.exists():
            runs = [d for d in out_root.iterdir() if d.is_dir()]
            runs.sort(key=lambda d: d.stat().st_mtime, reverse=True)
            for d in runs[:50]:
                # try common manifest names
                for fn in ["run_manifest.json", "run_gate_summary.json", "run_gate.json", "SUMMARY.txt"]:
                    fp = d / fn
                    if not fp.exists():
                        continue
                    try:
                        txt = fp.read_text(encoding="utf-8", errors="replace")
                    except Exception:
                        continue
                    # json
                    if fn.endswith(".json"):
                        try:
                            j = json.loads(txt)
                            rid = j.get("rid") or j.get("run_id") or j.get("id")
                            if rid:
                                return {"ok": True, "rid": str(rid), "source": f"out/{d.name}/{fn}"}
                        except Exception:
                            pass
                    # text
                    m = re.search(r'\b(RID|run_id)\s*[:=]\s*([A-Za-z0-9_\-\.]+)', txt)
                    if m:
                        return {"ok": True, "rid": m.group(2), "source": f"out/{d.name}/{fn}"}

        return {"ok": False, "rid": None, "source": "none"}
    except Exception as e:
        return {"ok": False, "rid": None, "error": str(e)}
'''

# inject route near other /api/vsp routes if possible; else append near end (before if __name__)
insert_pos = None
m = re.search(r'(?m)^\s*@app\.get\("/api/vsp/', s)
if m:
  insert_pos = m.start()
else:
  m2 = re.search(r'(?m)^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
  insert_pos = m2.start() if m2 else len(s)

s_new = s[:insert_pos] + route_code + "\n\n" + s[insert_pos:]
app.write_text(s_new, encoding="utf-8")
print("[OK] injected /api/vsp/latest_rid_v1")
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
