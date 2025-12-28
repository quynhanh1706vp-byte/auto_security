#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "[INFO] TS=$TS"
echo "[INFO] BASE=$BASE"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_runsv3wrap_${TS}"
echo "[BACKUP] ${W}.bak_runsv3wrap_${TS}"

python3 - <<'PY'
from pathlib import Path
import time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_APIUI_RUNS_V3_WRAPPER_P1_V1"
if marker in s:
    print("[OK] marker already present, skip:", marker)
else:
    block = r'''
# ===================== {MARKER} =====================
# Fix: /api/ui/runs_v3 404 under api/ui WSGI shim (force handle at outermost WSGI layer)
try:
    import os as __os
    import json as __json
    import time as __time
except Exception:
    __os = None; __json = None; __time = None

__VSP_RUNS_V3_CACHE = {"ts": 0, "data": None}

def __vsp__wsgi_json_bytes(payload, status=200):
    b = (__json.dumps(payload, ensure_ascii=False)).encode("utf-8")
    hdrs = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Cache-Control", "no-store"),
        ("Content-Length", str(len(b))),
    ]
    return status, hdrs, b

def __vsp__safe_int(x, d=0):
    try:
        return int(x)
    except Exception:
        return d

def __vsp__read_json(fp):
    try:
        with open(fp, "r", encoding="utf-8") as f:
            return __json.load(f)
    except Exception:
        return None

def __vsp__pick_overall(run_dir):
    if __os is None:
        return "UNKNOWN"
    cand = [
        __os.path.join(run_dir, "run_gate.json"),
        __os.path.join(run_dir, "run_gate_summary.json"),
        __os.path.join(run_dir, "SUMMARY.json"),
    ]
    for fp in cand:
        if __os.path.isfile(fp):
            j = __vsp__read_json(fp)
            if isinstance(j, dict):
                for k in ("overall_status","overall","status","verdict","final"):
                    v = j.get(k)
                    if isinstance(v, str) and v.strip():
                        return v.strip().upper()
                # nested variant
                ov = j.get("overall")
                if isinstance(ov, dict):
                    vv = ov.get("status") or ov.get("overall_status")
                    if isinstance(vv, str) and vv.strip():
                        return vv.strip().upper()
    return "UNKNOWN"

def __vsp__overall_weight(o):
    o = (o or "").upper()
    if "RED" in o: return 3
    if "AMBER" in o or "YELLOW" in o: return 2
    if "GREEN" in o: return 1
    return 0

def __vsp__findings_total(run_dir):
    if __os is None:
        return False, 0, None, None
    fp = __os.path.join(run_dir, "reports", "findings_unified.json")
    if not __os.path.isfile(fp):
        return False, 0, None, None
    j = __vsp__read_json(fp)
    total = 0
    counts = None
    if isinstance(j, dict):
        counts = j.get("counts")
        if isinstance(counts, dict):
            t = counts.get("TOTAL")
            if isinstance(t, int):
                total = t
            else:
                for k in ("total","total_findings"):
                    v = counts.get(k)
                    if isinstance(v, int):
                        total = v
                        break
        if total == 0:
            v = j.get("findings")
            if isinstance(v, list):
                total = len(v)
    elif isinstance(j, list):
        total = len(j)
    return True, int(total or 0), fp, counts if isinstance(counts, dict) else None

def __vsp__scan_runs_sorted(root="/home/test/Data/SECURITY_BUNDLE/out", cap=8000, cache_sec=8):
    # cache to avoid heavy scan on every poll
    if __time is None or __os is None:
        return []
    now = int(__time.time())
    if __VSP_RUNS_V3_CACHE["data"] is not None and now - int(__VSP_RUNS_V3_CACHE["ts"] or 0) <= cache_sec:
        return __VSP_RUNS_V3_CACHE["data"]

    items = []
    try:
        names = __os.listdir(root)
    except Exception:
        names = []
    runs = []
    for nm in names:
        if not nm.startswith("RUN_"):
            continue
        rd = __os.path.join(root, nm)
        if __os.path.isdir(rd):
            try:
                mt = int(__os.path.getmtime(rd))
            except Exception:
                mt = 0
            runs.append((mt, nm, rd))
    runs.sort(key=lambda x: x[0], reverse=True)

    for i, (mt, rid, rd) in enumerate(runs):
        if i >= cap:
            break
        has_f, ft, fpath, counts = __vsp__findings_total(rd)
        overall = __vsp__pick_overall(rd)
        items.append({
            "rid": rid,
            "run_dir": rd,
            "mtime": mt,
            "overall": overall,
            "has_findings": bool(has_f),
            "findings_total": int(ft),
            "findings_path": fpath,
            "counts": counts,
            "has_gate": __os.path.isfile(__os.path.join(rd, "run_gate.json")) or __os.path.isfile(__os.path.join(rd, "run_gate_summary.json")),
        })

    # sort “real data first”: findings_total desc, overall weight desc, mtime desc
    items.sort(key=lambda it: (
        int(it.get("findings_total", 0)),
        __vsp__overall_weight(it.get("overall")),
        int(it.get("mtime", 0)),
    ), reverse=True)

    __VSP_RUNS_V3_CACHE["ts"] = now
    __VSP_RUNS_V3_CACHE["data"] = items
    return items

try:
    __vsp__orig_application = application  # existing WSGI callable
except Exception:
    __vsp__orig_application = None

def __vsp__application_runs_v3_wrapper(environ, start_response):
    try:
        path = environ.get("PATH_INFO") or ""
        if path == "/api/ui/runs_v3":
            # parse query
            qs = environ.get("QUERY_STRING") or ""
            limit = 200
            offset = 0
            for part in qs.split("&"):
                if not part:
                    continue
                if part.startswith("limit="):
                    limit = __vsp__safe_int(part.split("=",1)[1], 200)
                elif part.startswith("offset="):
                    offset = __vsp__safe_int(part.split("=",1)[1], 0)
            limit = max(1, min(limit, 2000))
            offset = max(0, offset)

            items = __vsp__scan_runs_sorted()
            page = items[offset:offset+limit]
            status, hdrs, body = __vsp__wsgi_json_bytes({
                "ok": True,
                "items": page,
                "limit": limit,
                "offset": offset,
                "total": len(items),
                "sorted": "findings_total_desc,overall_weight_desc,mtime_desc",
                "ts": int(__time.time()) if __time else 0,
            }, 200)
            start_response(f"{status} OK", hdrs)
            return [body]
    except Exception as e:
        # fallthrough to original app
        pass

    if __vsp__orig_application is not None:
        return __vsp__orig_application(environ, start_response)

    # last resort 404
    status, hdrs, body = __vsp__wsgi_json_bytes({"ok": False, "error":"HTTP_404_NOT_FOUND", "path": environ.get("PATH_INFO",""), "ts": int(__time.time()) if __time else 0}, 404)
    start_response("404 NOT FOUND", hdrs)
    return [body]

# install wrapper once
try:
    if not globals().get("__VSP_RUNS_V3_WRAPPER_INSTALLED"):
        globals()["__VSP_RUNS_V3_WRAPPER_INSTALLED"] = True
        application = __vsp__application_runs_v3_wrapper
except Exception:
    pass
# =================== END {MARKER} ===================
'''.replace("{MARKER}", marker)

    s = s.rstrip() + "\n\n" + block + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", marker)
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart (no sudo) =="
bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || bin/p1_ui_8910_single_owner_start_v2.sh

echo "== verify runs_v3 now 200 =="
curl -fsS "$BASE/api/ui/runs_v3?limit=5&offset=0" | head -c 900; echo
echo "[DONE] If browser cached, hard-refresh /data_source (Ctrl+Shift+R)."
