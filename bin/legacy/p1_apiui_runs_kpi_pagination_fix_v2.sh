#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_runs_kpi_fix_${TS}"
echo "[BACKUP] ${W}.bak_runs_kpi_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_APIUI_RUNS_KPI_PAGINATION_COMPAT_P1_V2"
if marker in s:
    print("[OK] marker already present:", marker)
else:
    block = r'''
# ===================== {MARK} =====================
# Super-compat wrapper: add KPI + pagination endpoints for Runs & Reports
try:
    import os as __os, json as __json, time as __time
    import urllib.parse as __urlparse
    import re as __re

    def __vsp__json(start_response, obj, code=200):
        body = (__json.dumps(obj, ensure_ascii=False)).encode("utf-8")
        hdrs = [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("Content-Length", str(len(body))),
        ]
        start_response(f"{code} OK" if code==200 else f"{code} ERROR", hdrs)
        return [body]

    def __vsp__qs(environ):
        return __urlparse.parse_qs(environ.get("QUERY_STRING",""), keep_blank_values=True)

    def __vsp__get1(qs, k, default=None):
        v = qs.get(k)
        if not v: return default
        return v[0]

    def __vsp__int(x, d):
        try: return int(x)
        except Exception: return d

    def __vsp__safe_read_json(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return __json.load(f)
        except Exception:
            return None

    def __vsp__guess_overall(run_dir):
        # prefer JSON gates if exist
        cand = [
            "run_gate_summary.json",
            "run_gate.json",
            "verdict_4t.json",
            "gate.json",
            "SUMMARY.json",
        ]
        for fn in cand:
            fp = __os.path.join(run_dir, fn)
            if __os.path.isfile(fp):
                j = __vsp__safe_read_json(fp)
                if isinstance(j, dict):
                    for k in ("overall_status","overall","status","verdict"):
                        v = j.get(k)
                        if isinstance(v, str) and v.strip():
                            return v.strip().upper()
        # fallback SUMMARY.txt
        fp = __os.path.join(run_dir, "SUMMARY.txt")
        if __os.path.isfile(fp):
            try:
                t = open(fp, "r", encoding="utf-8", errors="ignore").read()
                m = __re.search(r"\boverall\b\s*[:=]\s*([A-Za-z]+)", t, flags=__re.I)
                if m: return m.group(1).upper()
            except Exception:
                pass
        return "UNKNOWN"

    def __vsp__norm_overall(x):
        x = (x or "").upper()
        if x in ("GREEN","PASS","OK","SUCCESS"): return "GREEN"
        if x in ("AMBER","WARN","WARNING","DEGRADED"): return "AMBER"
        if x in ("RED","FAIL","FAILED","ERROR","BLOCK"): return "RED"
        if x in ("UNKNOWN","NA","N/A","NONE",""): return "UNKNOWN"
        # keep other (but bucket as UNKNOWN)
        return "UNKNOWN"

    def __vsp__list_runs(out_root, max_scan=2000):
        items = []
        try:
            if not __os.path.isdir(out_root):
                return items
            for name in __os.listdir(out_root):
                if not name.startswith("RUN_"):
                    continue
                run_dir = __os.path.join(out_root, name)
                if not __os.path.isdir(run_dir):
                    continue
                try:
                    mtime = int(__os.path.getmtime(run_dir))
                except Exception:
                    mtime = 0
                items.append((mtime, name, run_dir))
        except Exception:
            return []
        items.sort(key=lambda x: (x[0], x[1]), reverse=True)
        if len(items) > max_scan:
            items = items[:max_scan]
        return items

    def __vsp__runs_page_payload(out_root, limit, offset):
        all_items = __vsp__list_runs(out_root)
        total = len(all_items)
        limit = max(1, min(limit, 200))
        offset = max(0, min(offset, total))
        page = all_items[offset:offset+limit]
        out = []
        for mtime, rid, run_dir in page:
            o = __vsp__norm_overall(__vsp__guess_overall(run_dir))
            out.append({"rid": rid, "run_dir": run_dir, "mtime": mtime, "overall": o})
        page_total = (total + limit - 1)//limit if total>0 else 1
        page_no = (offset//limit) + 1 if total>0 else 1
        return {
            "ok": True,
            "items": out,
            "limit": limit,
            "offset": offset,
            "total": total,
            "page_no": page_no,
            "page_total": page_total,
            "next_offset": (offset+limit if offset+limit < total else None),
            "prev_offset": (offset-limit if offset-limit >= 0 else None),
            "ts": int(__time.time()),
        }

    def __vsp__runs_kpi_payload(out_root, max_scan=2000):
        all_items = __vsp__list_runs(out_root, max_scan=max_scan)
        buckets = {"GREEN":0,"AMBER":0,"RED":0,"UNKNOWN":0}
        latest = all_items[0][1] if all_items else None
        for mtime, rid, run_dir in all_items:
            o = __vsp__norm_overall(__vsp__guess_overall(run_dir))
            buckets[o] = buckets.get(o,0) + 1
        return {
            "ok": True,
            "total_runs": len(all_items),
            "by_overall": buckets,
            "latest_rid": latest,
            "scan_cap": max_scan,
            "ts": int(__time.time()),
        }

    def __vsp__wrap_wsgi(inner):
        OUT_ROOT = "/home/test/Data/SECURITY_BUNDLE/out"
        def _app(environ, start_response):
            path = environ.get("PATH_INFO","") or ""
            qs = __vsp__qs(environ)

            # --- KPI endpoints (accept multiple names) ---
            if path in ("/api/ui/runs_kpi", "/api/ui/runs_kpi_v1", "/api/ui/runs_kpi_v2", "/api/ui/runs_kpi_v3"):
                cap = __vsp__int(__vsp__get1(qs,"cap", "2000"), 2000)
                return __vsp__json(start_response, __vsp__runs_kpi_payload(OUT_ROOT, max_scan=cap), 200)

            # --- Pagination endpoints (accept multiple names) ---
            if path in ("/api/ui/runs_page", "/api/ui/runs_page_v1", "/api/ui/runs_page_v2", "/api/ui/runs_paged_v1"):
                limit = __vsp__int(__vsp__get1(qs,"limit","20"), 20)
                offset = __vsp__int(__vsp__get1(qs,"offset","0"), 0)
                return __vsp__json(start_response, __vsp__runs_page_payload(OUT_ROOT, limit, offset), 200)

            # --- Upgrade runs_v2 to support offset (compat with UI pagination) ---
            if path == "/api/ui/runs_v2":
                limit = __vsp__int(__vsp__get1(qs,"limit","200"), 200)
                offset = __vsp__int(__vsp__get1(qs,"offset","0"), 0)
                return __vsp__json(start_response, __vsp__runs_page_payload(OUT_ROOT, limit, offset), 200)

            return inner(environ, start_response)
        return _app

    __inner = globals().get("application") or globals().get("app")
    if __inner:
        __wrapped = __vsp__wrap_wsgi(__inner)
        globals()["application"] = __wrapped
        globals()["app"] = __wrapped
except Exception:
    pass
# =================== END {MARK} ===================
'''.replace("{MARK}", marker)

    s = s + "\n" + block
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", marker)
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart (no sudo) =="
bash bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || bash bin/p1_ui_8910_single_owner_start_v2.sh

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify endpoints =="
for u in \
  "$BASE/api/ui/runs_kpi_v1" \
  "$BASE/api/ui/runs_page_v1?limit=10&offset=0" \
  "$BASE/api/ui/runs_v2?limit=10&offset=10"
do
  echo "--- $u"
  curl -fsS "$u" | head -c 220; echo
done

echo "[DONE] runs KPI + pagination compat installed."
