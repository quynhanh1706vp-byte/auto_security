#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need awk; need wc; need head
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl not found"; exit 2; }

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p36_wrap_${TS}"
echo "[BACKUP] ${W}.bak_p36_wrap_${TS}"

python3 - <<'PY'
from pathlib import Path
import os, re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P36_PAGING_RID_WRAP_V1"
blk_pat=re.compile(r"(?s)\n# --- "+re.escape(MARK)+r" ---.*?\n# --- /"+re.escape(MARK)+r" ---\n")
if blk_pat.search(s):
    print("[OK] already installed:", MARK)
else:
    block=f"""
# --- {MARK} ---
# Commercial P36: enforce paging for /api/vsp/findings and RID correctness for /api/vsp/datasource_v2?rid=...
__vsp_p36_wrap_installed = globals().get("__vsp_p36_wrap_installed", False)

def __vsp_p36_json(start_response, obj, code=200, extra_headers=None):
    import json, time
    if isinstance(obj, dict) and "ts" not in obj:
        obj["ts"] = int(time.time())
    body = (json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\\n").encode("utf-8", "replace")
    hdrs = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store"),
    ]
    if extra_headers:
        for k,v in extra_headers:
            hdrs.append((k,v))
    start_response(f"{code} OK", hdrs)
    return [body]

def __vsp_p36_qs(environ):
    import urllib.parse
    return urllib.parse.parse_qs(environ.get("QUERY_STRING") or "")

def __vsp_p36_int(qs, key, default, lo=0, hi=1000):
    try:
        v = int((qs.get(key, [str(default)])[0] or str(default)).strip())
    except Exception:
        v = default
    if v < lo: v = lo
    if v > hi: v = hi
    return v

def __vsp_p36_load_items_from_file(path):
    import json, os
    if not path or not os.path.isfile(path):
        return None
    try:
        j = json.load(open(path, "r", encoding="utf-8"))
    except Exception:
        return []
    if isinstance(j, dict):
        it = j.get("items")
        if isinstance(it, list):
            return it
        # fallback common keys
        for k in ("findings", "results", "data"):
            if isinstance(j.get(k), list):
                return j.get(k)
        return []
    if isinstance(j, list):
        return j
    return []

def __vsp_p36_resolve_rid_file(rid):
    import os
    if not rid:
        return None
    roots = []
    # env overrides (optional)
    for ev in ("VSP_OUT_CI_DIR", "VSP_OUT_DIR", "RUNS_ROOT", "VSP_RUNS_ROOT"):
        v=os.environ.get(ev) or ""
        if v.strip():
            roots.append(v.strip())
    # known defaults
    roots += [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]
    cand = []
    for r in roots:
        cand += [
            os.path.join(r, rid, "findings_unified.json"),
            os.path.join(r, rid, "reports", "findings_unified.json"),
            os.path.join(r, rid, "report", "findings_unified.json"),
        ]
    for fp in cand:
        if os.path.isfile(fp):
            return fp
    return None

try:
    if not __vsp_p36_wrap_installed:
        __vsp_app_prev_p36 = globals().get("application")
        # Guard: do not wrap if missing or already wrapped
        if callable(__vsp_app_prev_p36) and not getattr(__vsp_app_prev_p36, "__vsp_p36__", False):

            def application(environ, start_response):
                try:
                    path = (environ.get("PATH_INFO") or "")
                    p = path[:-1] if (path.endswith("/") and path != "/") else path
                    method = (environ.get("REQUEST_METHOD") or "GET").upper()
                    qs = __vsp_p36_qs(environ)

                    # (A) /api/vsp/findings paging
                    if p == "/api/vsp/findings" and method == "GET":
                        limit = __vsp_p36_int(qs, "limit", 50, lo=1, hi=500)
                        offset = __vsp_p36_int(qs, "offset", 0, lo=0, hi=10_000_000)
                        src = "/home/test/Data/SECURITY_BUNDLE/ui/findings_unified.json"
                        items = __vsp_p36_load_items_from_file(src)
                        if items is None:
                            return __vsp_p36_json(start_response, {
                                "ok": False, "reason": "missing_file", "file": src,
                                "items": [], "total": 0, "limit": limit, "offset": offset
                            })
                        total = len(items)
                        slice_ = items[offset: offset + limit] if offset < total else []
                        warn = "offset_out_of_range" if (offset >= total and total > 0) else ""
                        return __vsp_p36_json(start_response, {
                            "ok": True, "file": src,
                            "total": total, "limit": limit, "offset": offset,
                            "items": slice_, "warning": warn
                        })

                    # (B) /api/vsp/datasource_v2 rid correctness + paging when rid provided
                    if p == "/api/vsp/datasource_v2" and method == "GET":
                        rid = (qs.get("rid", [""])[0] or "").strip()
                        if rid:
                            fp = __vsp_p36_resolve_rid_file(rid)
                            if not fp:
                                return __vsp_p36_json(start_response, {
                                    "ok": False, "rid": rid, "reason": "run_dir_not_found",
                                    "items": [], "total": 0, "resolve_source": "not_found"
                                })
                            items = __vsp_p36_load_items_from_file(fp) or []
                            limit = __vsp_p36_int(qs, "limit", 200, lo=1, hi=1000)
                            offset = __vsp_p36_int(qs, "offset", 0, lo=0, hi=10_000_000)
                            total = len(items)
                            slice_ = items[offset: offset + limit] if offset < total else []
                            warn = "offset_out_of_range" if (offset >= total and total > 0) else ""
                            return __vsp_p36_json(start_response, {
                                "ok": True, "rid": rid, "file": fp, "resolve_source": "rid_file",
                                "total": total, "limit": limit, "offset": offset,
                                "items": slice_, "warning": warn
                            })

                except Exception as e:
                    return __vsp_p36_json(start_response, {"ok": False, "reason": "exception", "error": str(e)}, code=200)

                # default: pass-through (V5 + original app)
                return __vsp_app_prev_p36(environ, start_response)

            application.__vsp_p36__ = True
            globals()["__vsp_p36_wrap_installed"] = True
except Exception:
    pass
# --- /{MARK} ---
"""
    s = s.rstrip() + "\n" + block + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", MARK)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [restart] =="
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" || true

echo "== [warm] =="
ok=0
for i in $(seq 1 60); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
    echo "[OK] selfcheck ok (try#$i)"; ok=1; break
  fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] selfcheck failing"; exit 2; }

echo "== [CHECK] findings paging size should be small now =="
curl -sS -D /tmp/_h -o /tmp/_b "$BASE/api/vsp/findings?limit=5&offset=0"
awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Length:/{print}' /tmp/_h
echo "body_bytes=$(wc -c </tmp/_b)"
head -c 220 /tmp/_b; echo; echo

echo "== [CHECK] datasource_v2 rid missing should be ok:false now =="
curl -sS -D /tmp/_h2 -o /tmp/_b2 "$BASE/api/vsp/datasource_v2?rid=RID_DOES_NOT_EXIST_123&limit=5&offset=0"
awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Length:/{print}' /tmp/_h2
head -c 220 /tmp/_b2; echo
