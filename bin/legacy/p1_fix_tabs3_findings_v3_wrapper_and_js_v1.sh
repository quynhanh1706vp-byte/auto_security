#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need grep; need awk

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"
echo "[INFO] BASE=$BASE"

W="wsgi_vsp_ui_gateway.py"
JS="static/js/vsp_data_source_tab_v3.js"
JS2="static/js/vsp_rule_overrides_tab_v3.js"

[ -f "$W" ]  || { echo "[ERR] missing $W"; exit 2; }
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$W"  "${W}.bak_findingsv3_${TS}"
cp -f "$JS" "${JS}.bak_findingsv3_${TS}"
[ -f "$JS2" ] && cp -f "$JS2" "${JS2}.bak_findingsv3_${TS}" || true
echo "[BACKUP] ${W}.bak_findingsv3_${TS}"
echo "[BACKUP] ${JS}.bak_findingsv3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")

marker = "VSP_APIUI_FINDINGS_V3_WRAPPER_P1_V1"
if marker in s:
    print("[OK] marker already present:", marker)
else:
    block = textwrap.dedent(r'''
    # --- VSP_APIUI_FINDINGS_V3_WRAPPER_P1_V1 ---
    # Safe wrapper for /api/ui/findings_v3 to avoid 500/bad_json & bypass flask routing issues under /api/ui/*
    import os, json, time, urllib.parse

    def __vsp__json_bytes(obj):
        return (json.dumps(obj, ensure_ascii=False).encode("utf-8"))

    def __vsp__wsgi_json(start_response, obj, code="200 OK"):
        body = __vsp__json_bytes(obj)
        headers = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Cache-Control", "no-store"),
            ("Content-Length", str(len(body))),
        ]
        start_response(code, headers)
        return [body]

    def __vsp__parse_qs(environ):
        qs = environ.get("QUERY_STRING","")
        q = urllib.parse.parse_qs(qs, keep_blank_values=True)
        def one(k, d=None):
            v = q.get(k)
            return (v[0] if v else d)
        return q, one

    __vsp__FINDINGS_CACHE = {"runs": None, "ts": 0}

    def __vsp__scan_runs(out_root):
        items = []
        try:
            for name in os.listdir(out_root):
                if not name.startswith("RUN_"):
                    continue
                run_dir = os.path.join(out_root, name)
                if not os.path.isdir(run_dir):
                    continue
                f1 = os.path.join(run_dir, "reports", "findings_unified.json")
                f2 = os.path.join(run_dir, "reports", "findings_unified.json".replace("reports/",""))  # no-op safety
                f = f1 if os.path.exists(f1) else (f2 if os.path.exists(f2) else None)
                has_findings = bool(f)
                mtime = int(os.path.getmtime(run_dir)) if os.path.exists(run_dir) else 0
                items.append({"rid": name, "run_dir": run_dir, "mtime": mtime, "has_findings": has_findings, "findings_path": f})
        except Exception:
            return []
        return items

    def __vsp__get_run(out_root, rid):
        # cache for 10s to reduce listdir spam
        now = time.time()
        if (__vsp__FINDINGS_CACHE["runs"] is None) or (now - __vsp__FINDINGS_CACHE["ts"] > 10):
            __vsp__FINDINGS_CACHE["runs"] = __vsp__scan_runs(out_root)
            __vsp__FINDINGS_CACHE["ts"] = now
        for it in (__vsp__FINDINGS_CACHE["runs"] or []):
            if it.get("rid") == rid:
                return it
        # fallback direct path
        run_dir = os.path.join(out_root, rid)
        f = os.path.join(run_dir, "reports", "findings_unified.json")
        if os.path.exists(f):
            return {"rid": rid, "run_dir": run_dir, "mtime": int(os.path.getmtime(run_dir)), "has_findings": True, "findings_path": f}
        return None

    def __vsp__load_findings(fp):
        try:
            j = json.load(open(fp, "r", encoding="utf-8"))
        except Exception as e:
            return None, "bad_json", str(e)
        # schema variants:
        # - dict with findings:list + counts
        # - dict with items/list keys
        # - raw list
        if isinstance(j, dict):
            if isinstance(j.get("findings"), list):
                return {"items": j["findings"], "counts": (j.get("counts") or {})}, "ok", None
            for k in ("items","results","data"):
                if isinstance(j.get(k), list):
                    return {"items": j[k], "counts": (j.get("counts") or {})}, f"ok_dict_{k}", None
            return {"items": [], "counts": (j.get("counts") or {})}, "ok_empty_dict", None
        if isinstance(j, list):
            return {"items": j, "counts": {}}, "ok_list", None
        return None, "bad_shape", f"type={type(j).__name__}"

    def __vsp__count_sev(items):
        # best-effort counts
        sev_keys = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]
        c = {k: 0 for k in sev_keys}
        for it in items:
            sv = None
            if isinstance(it, dict):
                sv = (it.get("severity") or it.get("sev") or it.get("level"))
            if sv:
                sv = str(sv).upper().strip()
                if sv in c: c[sv] += 1
        c["TOTAL"] = sum(c.values())
        return c

    def __vsp__norm_item(it):
        if not isinstance(it, dict):
            return {"tool":"", "severity":"INFO", "title":"Finding", "rule_id":"", "file":"", "line":0, "message":str(it)[:500]}
        tool = it.get("tool") or it.get("engine") or it.get("source") or ""
        sev  = (it.get("severity") or it.get("sev") or it.get("level") or "INFO")
        sev  = str(sev).upper().strip()
        title = it.get("title") or it.get("name") or "Finding"
        rule_id = it.get("rule_id") or it.get("rule") or it.get("check_id") or ""
        file_ = it.get("file") or it.get("path") or it.get("filename") or ""
        line  = it.get("line") or it.get("line_number") or 0
        msg   = it.get("message") or it.get("msg") or it.get("description") or ""
        return {"tool": str(tool), "severity": sev, "title": str(title), "rule_id": str(rule_id),
                "file": str(file_), "line": int(line) if str(line).isdigit() else 0, "message": str(msg)}

    def __vsp__handle_findings_v3(environ, start_response):
        out_root = os.environ.get("VSP_OUT_ROOT", "/home/test/Data/SECURITY_BUNDLE/out")
        _, one = __vsp__parse_qs(environ)
        rid = one("rid", "")
        if not rid:
            return __vsp__wsgi_json(start_response, {"ok": False, "error":"missing_rid", "path": environ.get("PATH_INFO",""), "ts": int(time.time())}, "400 BAD REQUEST")
        limit = one("limit","50")
        offset = one("offset","0")
        try:
            limit = max(1, min(500, int(limit)))
        except Exception:
            limit = 50
        try:
            offset = max(0, int(offset))
        except Exception:
            offset = 0

        run = __vsp__get_run(out_root, rid)
        if not run or not run.get("findings_path"):
            return __vsp__wsgi_json(start_response, {"ok": False, "error":"missing_findings_file", "rid": rid, "out_root": out_root, "ts": int(time.time())}, "404 NOT FOUND")

        fp = run["findings_path"]
        payload, st, err = __vsp__load_findings(fp)
        if payload is None:
            return __vsp__wsgi_json(start_response, {"ok": False, "error": st, "rid": rid, "findings_path": fp, "detail": err, "ts": int(time.time())}, "200 OK")

        items_all = payload["items"] or []
        total = len(items_all)
        page = items_all[offset: offset+limit]
        page2 = [__vsp__norm_item(x) for x in page]

        counts = payload.get("counts") or {}
        if not isinstance(counts, dict) or not counts:
            # if file has no counts, compute from all items (can be heavy but accurate)
            counts = __vsp__count_sev(items_all)

        # overall best-effort: read run_gate.json if exists
        overall = "UNKNOWN"
        try:
            gate_fp = os.path.join(run["run_dir"], "run_gate.json")
            if os.path.exists(gate_fp):
                g = json.load(open(gate_fp, "r", encoding="utf-8"))
                overall = (g.get("overall") or g.get("overall_status") or overall)
        except Exception:
            pass

        return __vsp__wsgi_json(start_response, {
            "ok": True,
            "rid": rid,
            "run_dir": run.get("run_dir"),
            "overall": overall,
            "items": page2,
            "counts": {k: int(counts.get(k,0)) for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]} | {"TOTAL": int(counts.get("TOTAL", total))},
            "limit": limit,
            "offset": offset,
            "total": total,
            "findings_path": fp,
            "schema": st,
            "ts": int(time.time()),
        }, "200 OK")

    def __vsp__wrap_wsgi_for_findings_v3(inner_app):
        def _w(environ, start_response):
            path = environ.get("PATH_INFO","")
            if path == "/api/ui/findings_v3":
                return __vsp__handle_findings_v3(environ, start_response)
            return inner_app(environ, start_response)
        return _w

    # install wrapper on Flask app if present, else on 'application'
    try:
        if "app" in globals() and hasattr(globals()["app"], "wsgi_app"):
            globals()["app"].wsgi_app = __vsp__wrap_wsgi_for_findings_v3(globals()["app"].wsgi_app)
    except Exception:
        pass

    try:
        if "application" in globals() and callable(globals()["application"]):
            globals()["application"] = __vsp__wrap_wsgi_for_findings_v3(globals()["application"])
    except Exception:
        pass
    # --- END VSP_APIUI_FINDINGS_V3_WRAPPER_P1_V1 ---
    ''').strip("\n") + "\n"

    s = s + "\n\n" + block
    w.write_text(s, encoding="utf-8")
    print("[OK] appended:", marker)

PY

# Patch Data Source JS to pin endpoints to runs_v3 + findings_v3 (safe)
python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_data_source_tab_v3.js")
s = p.read_text(encoding="utf-8", errors="replace")

orig = s

# force runs list endpoint -> runs_v3
s = re.sub(r'"/api/ui/runs_v[0-9][^"]*"', '"/api/ui/runs_v3?limit=200&offset=0"', s)
s = re.sub(r'"/api/ui/runs_v2\?limit=\d+"', '"/api/ui/runs_v3?limit=200&offset=0"', s)
s = re.sub(r'"/api/ui/runs_v1\?limit=\d+"', '"/api/ui/runs_v3?limit=200&offset=0"', s)

# force findings endpoint -> findings_v3 (safe)
s = re.sub(r'"/api/ui/findings_v[0-9][^"]*"', '"/api/ui/findings_v3"', s)
s = re.sub(r'"/api/ui/findings[^"]*"', '"/api/ui/findings_v3"', s)

# if code concatenates strings like "/api/ui/findings_v2?rid=" -> normalize
s = re.sub(r'/api/ui/findings_v[0-9]\?rid=', r'/api/ui/findings_v3?rid=', s)
s = re.sub(r'/api/ui/findings\?rid=', r'/api/ui/findings_v3?rid=', s)

p.write_text(s, encoding="utf-8")
print("[OK] patched vsp_data_source_tab_v3.js changed=", (s != orig))
PY

# Patch Rule Overrides tab to also consume runs_v3 (for dropdown)
if [ -f "$JS2" ]; then
python3 - <<'PY'
from pathlib import Path
import re
p = Path("static/js/vsp_rule_overrides_tab_v3.js")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s
s = re.sub(r'/api/ui/runs_v[0-9]\?limit=\d+', '/api/ui/runs_v3?limit=200&offset=0', s)
s = re.sub(r'/api/ui/runs_v2\?limit=\d+', '/api/ui/runs_v3?limit=200&offset=0', s)
p.write_text(s, encoding="utf-8")
print("[OK] patched vsp_rule_overrides_tab_v3.js changed=", (s != orig))
PY
fi

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart (unlock+single-owner) =="
if [ -x "bin/p1_force_restart_8910_unlock_v1.sh" ]; then
  bash bin/p1_force_restart_8910_unlock_v1.sh
else
  echo "[WARN] missing bin/p1_force_restart_8910_unlock_v1.sh -> please restart gunicorn manually"
fi

echo "== verify endpoints =="
echo "--- runs_v3"
curl -fsS "$BASE/api/ui/runs_v3?limit=3&offset=0" | head -c 800; echo

RID="$(curl -fsS "$BASE/api/ui/runs_v3?limit=50&offset=0" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
rid=""
for it in j.get("items",[]):
    if it.get("has_findings") and int(it.get("findings_total",0))>0:
        rid=it.get("rid"); break
print(rid)
PY
)"
if [ -z "${RID:-}" ]; then
  RID="RUN_20251120_130310"
fi
echo "[RID] $RID"

echo "--- findings_v3 (must ok:true & total>0)"
curl -fsS "$BASE/api/ui/findings_v3?rid=$RID&limit=1&offset=0" | head -c 1000; echo

echo "[DONE] Now hard-refresh Data Source (Ctrl+Shift+R). Pick RID=$RID and you should see counts + rows."
