#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_runs_kpi_${TS}"
echo "[BACKUP] ${W}.bak_runs_kpi_${TS}"

python3 - <<'PY'
from pathlib import Path
import time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_APIUI_RUNS_KPI_PAGINATION_P1_V1"
if marker in s:
    print("[OK] marker already present, skip")
    raise SystemExit(0)

append = r'''
# ==== {marker} ====
try:
    import os as __os, json as __json, time as __time
    from urllib.parse import parse_qs as __parse_qs
except Exception:
    pass

def __apiui_qs(environ):
    try:
        return __parse_qs(environ.get("QUERY_STRING",""), keep_blank_values=True)
    except Exception:
        return {}

def __apiui_int(qs, k, default):
    try:
        v = (qs.get(k,[None])[0])
        if v is None or v == "": return default
        return int(v)
    except Exception:
        return default

def __apiui_read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return __json.load(f)
    except Exception:
        return None

def __apiui_pick_overall(run_dir):
    # prefer run_gate_summary.json then run_gate.json
    for fn in ("run_gate_summary.json", "run_gate.json"):
        j = __apiui_read_json(__os.path.join(run_dir, fn))
        if not isinstance(j, dict): 
            continue
        for k in ("overall", "overall_status", "overall_status_final"):
            v = j.get(k)
            if isinstance(v, str) and v.strip():
                return v.strip()
    return "UNKNOWN"

def __apiui_list_runs():
    out_root = "/home/test/Data/SECURITY_BUNDLE/out"
    try:
        names = []
        for name in __os.listdir(out_root):
            if name.startswith("RUN_"):
                run_dir = __os.path.join(out_root, name)
                try:
                    st = __os.stat(run_dir)
                    names.append((st.st_mtime, name, run_dir))
                except Exception:
                    names.append((0, name, run_dir))
        names.sort(key=lambda t: t[0], reverse=True)
        return names
    except Exception:
        return []

def __apiui_runs_page(environ):
    qs = __apiui_qs(environ)
    limit  = __apiui_int(qs, "limit", 20)
    offset = __apiui_int(qs, "offset", 0)
    limit = max(1, min(limit, 200))
    offset = max(0, offset)

    runs = __apiui_list_runs()
    total = len(runs)
    sl = runs[offset:offset+limit]

    items = []
    for mtime, rid, run_dir in sl:
        items.append({
            "rid": rid,
            "run_dir": run_dir,
            "mtime": int(mtime or 0),
            "overall": __apiui_pick_overall(run_dir),
        })

    return {
        "ok": True,
        "items": items,
        "limit": limit,
        "offset": offset,
        "total": total,
        "has_more": (offset + limit) < total,
        "ts": int(__time.time()),
    }

def __apiui_runs_kpi():
    runs = __apiui_list_runs()
    total = len(runs)
    sample = runs[:200]  # cap for speed
    c = {"GREEN":0, "AMBER":0, "RED":0, "UNKNOWN":0}
    last = None
    for mtime, rid, run_dir in sample:
        ov = __apiui_pick_overall(run_dir).upper()
        if ov not in c:
            ov = "UNKNOWN"
        c[ov] += 1
        if last is None:
            last = {"rid": rid, "mtime": int(mtime or 0), "overall": ov}
    return {
        "ok": True,
        "kpi": {
            "total_runs": total,
            "sampled": len(sample),
            "by_overall": c,
            "latest": last or {"rid":"", "mtime":0, "overall":"UNKNOWN"},
        },
        "ts": int(__time.time()),
    }

# Patch into existing WSGI shim dispatcher:
# We add a tiny wrapper at bottom that intercepts paths we want.
def __apiui_extra_dispatch(app):
    def _wsgi(environ, start_response):
        try:
            path = environ.get("PATH_INFO","")
            if path == "/api/ui/runs_page_v1":
                return __wsgi_json(__apiui_runs_page(environ), 200)(environ, start_response)
            if path == "/api/ui/runs_kpi_v1":
                return __wsgi_json(__apiui_runs_kpi(), 200)(environ, start_response)
        except Exception as e:
            try:
                return __wsgi_json({"ok": False, "error": "apiui_extra_dispatch", "detail": str(e), "ts": int(__time.time())}, 200)(environ, start_response)
            except Exception:
                pass
        return app(environ, start_response)
    return _wsgi
# ==== /{marker} ====
'''.replace("{marker}", marker)

# append at end
s2 = s + "\n" + append + "\n"

# now wrap final 'application' if present, else wrap 'app'
# Try common names used in your gateway:
for var in ("application", "app"):
    if f"{var} = __apiui_extra_dispatch({var})" in s2:
        break
else:
    # append wrapper wiring
    s2 += "\ntry:\n"
    s2 += "    application = __apiui_extra_dispatch(application)\n"
    s2 += "except Exception:\n"
    s2 += "    try:\n"
    s2 += "        app = __apiui_extra_dispatch(app)\n"
    s2 += "    except Exception:\n"
    s2 += "        pass\n"

p.write_text(s2, encoding="utf-8")
print("[OK] appended:", marker)
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart (no sudo) =="
VSP_UI_BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}" bin/p1_ui_8910_single_owner_start_v2.sh || true
sleep 1

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify new endpoints =="
curl -fsS "$BASE/api/ui/runs_page_v1?limit=2&offset=0" | head -c 220; echo
curl -fsS "$BASE/api/ui/runs_page_v1?limit=2&offset=2" | head -c 220; echo
curl -fsS "$BASE/api/ui/runs_kpi_v1" | head -c 220; echo
echo "[DONE] runs KPI + pagination API ready"
