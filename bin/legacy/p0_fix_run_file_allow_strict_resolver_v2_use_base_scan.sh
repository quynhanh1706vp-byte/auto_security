#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need head
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID_A="${1:-VSP_CI_20251219_092640}"
RID_B="${2:-VSP_CI_20251211_133204}"

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P0_RUN_FILE_ALLOW_STRICT_PER_RID_V2_BASESCAN"
cp -f "$WSGI" "${WSGI}.bak_${MARK}_${TS}"
ok "backup: ${WSGI}.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_P0_RUN_FILE_ALLOW_STRICT_PER_RID_V2_BASESCAN"
if MARK in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

block = r'''
# --- VSP_P0_RUN_FILE_ALLOW_STRICT_PER_RID_V2_BASESCAN ---
import os as _vsp_os_rfa2
import json as _vsp_json_rfa2
import urllib.parse as _vsp_urlparse_rfa2
import time as _vsp_time_rfa2

_RFA2_CACHE = {"rid2dir": {}, "roots": None, "roots_ts": 0}

def _rfa2_json(payload: dict):
    body=_vsp_json_rfa2.dumps(payload, ensure_ascii=False).encode("utf-8")
    return [(
        b"HTTP/1.1 200 OK\r\n"
        b"Content-Type: application/json; charset=utf-8\r\n"
        b"Cache-Control: no-store\r\n"
        b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n\r\n"
    ) + body]

def _rfa2_safe_rel(path: str) -> str:
    path=(path or "").strip()
    if not path or path.startswith("/") or "\x00" in path:
        return ""
    parts=[p for p in path.split("/") if p not in ("", ".")]
    if any(p==".." for p in parts):
        return ""
    return "/".join(parts)

def _rfa2_collect_roots():
    # Refresh roots every 60s (in case env changes)
    now=int(_vsp_time_rfa2.time())
    if _RFA2_CACHE["roots"] is not None and now - _RFA2_CACHE["roots_ts"] < 60:
        return _RFA2_CACHE["roots"]

    roots=[]

    # (1) env roots
    for env in ("VSP_GATE_ROOT","VSP_RUNS_ROOT","VSP_RUN_ROOT","VSP_OUT_CI_ROOT","VSP_OUT_ROOT"):
        v=_vsp_os_rfa2.environ.get(env)
        if v and _vsp_os_rfa2.path.isdir(v) and v not in roots:
            roots.append(v)

    # (2) module globals roots (reuse system's own base)
    g=globals()
    for k in ("_base","BASE_DIR","GATE_ROOT","RUNS_ROOT","OUT_ROOT","OUT_CI_ROOT"):
        v=g.get(k)
        if isinstance(v,str) and v and _vsp_os_rfa2.path.isdir(v) and v not in roots:
            roots.append(v)

    # (3) sane defaults (keep but don't rely on them)
    for d in (
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out",
    ):
        if _vsp_os_rfa2.path.isdir(d) and d not in roots:
            roots.append(d)

    _RFA2_CACHE["roots"]=roots
    _RFA2_CACHE["roots_ts"]=now
    return roots

def _rfa2_find_dir_direct(rid: str):
    roots=_rfa2_collect_roots()
    for root in roots:
        cand=_vsp_os_rfa2.path.join(root, rid)
        if _vsp_os_rfa2.path.isdir(cand):
            return cand
    return None

def _rfa2_scan_find_dir(rid: str, max_depth: int = 3):
    # Depth-limited scan across roots; cached per rid. Only used when direct lookup fails.
    if rid in _RFA2_CACHE["rid2dir"]:
        return _RFA2_CACHE["rid2dir"][rid]

    roots=_rfa2_collect_roots()
    for root in roots:
        # BFS depth-limited
        q=[(root,0)]
        seen=set()
        while q:
            cur,depth=q.pop(0)
            if cur in seen: 
                continue
            seen.add(cur)
            try:
                base=_vsp_os_rfa2.path.basename(cur.rstrip("/"))
                if base == rid and _vsp_os_rfa2.path.isdir(cur):
                    _RFA2_CACHE["rid2dir"][rid]=cur
                    return cur
                if depth >= max_depth:
                    continue
                # list children dirs only
                for name in _vsp_os_rfa2.listdir(cur):
                    if name.startswith("."):
                        continue
                    p=_vsp_os_rfa2.path.join(cur,name)
                    if _vsp_os_rfa2.path.isdir(p):
                        q.append((p, depth+1))
            except Exception:
                continue

    _RFA2_CACHE["rid2dir"][rid]=None
    return None

def _rfa2_resolve_file(run_dir: str, rel: str):
    cands=[rel]
    if not rel.startswith("reports/"):
        cands.append("reports/"+rel)
    if not rel.startswith("report/"):
        cands.append("report/"+rel)
    seen=set()
    for r in cands:
        if r in seen: 
            continue
        seen.add(r)
        fp=_vsp_os_rfa2.path.join(run_dir, r)
        if _vsp_os_rfa2.path.isfile(fp):
            return fp, r
    return None, None

class _VspRunFileAllowStrictPerRidMwV2:
    """
    V2: strict per RID, but uses system base/env roots, plus depth-limited scan (cached).
    """
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        if (environ.get("PATH_INFO") or "") != "/api/vsp/run_file_allow":
            return self.app(environ, start_response)

        qs=_vsp_urlparse_rfa2.parse_qs(environ.get("QUERY_STRING",""))
        rid_req=(qs.get("rid",[""])[0] or "").strip()
        req_path=(qs.get("path",[""])[0] or "").strip()
        limit_s=(qs.get("limit",[""])[0] or "").strip()

        if not rid_req:
            payload={"ok":False,"error":"RID_REQUIRED","rid_req":"","rid_used":"","from":"","data":None}
            start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store")],None)
            return [ _vsp_json_rfa2.dumps(payload,ensure_ascii=False).encode("utf-8") ]

        rel=_rfa2_safe_rel(req_path)
        if not rel:
            payload={"ok":False,"error":"INVALID_PATH","rid_req":rid_req,"rid_used":rid_req,"from":f"{rid_req}/{req_path}","data":None}
            start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store")],None)
            return [ _vsp_json_rfa2.dumps(payload,ensure_ascii=False).encode("utf-8") ]

        run_dir=_rfa2_find_dir_direct(rid_req) or _rfa2_scan_find_dir(rid_req, max_depth=3)
        if not run_dir:
            payload={"ok":False,"error":"RID_NOT_FOUND","rid_req":rid_req,"rid_used":rid_req,"from":f"{rid_req}/{rel}","data":None}
            start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store")],None)
            return [ _vsp_json_rfa2.dumps(payload,ensure_ascii=False).encode("utf-8") ]

        fp, rel_used=_rfa2_resolve_file(run_dir, rel)
        if not fp:
            payload={"ok":False,"error":"FILE_NOT_FOUND","rid_req":rid_req,"rid_used":rid_req,"from":f"{rid_req}/{rel}","data":None}
            start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store")],None)
            return [ _vsp_json_rfa2.dumps(payload,ensure_ascii=False).encode("utf-8") ]

        try:
            raw=open(fp,"rb").read()
            try:
                data=_vsp_json_rfa2.loads(raw.decode("utf-8","ignore") or "{}")
            except Exception:
                data={"_raw_text": raw.decode("utf-8","ignore")}
        except Exception as e:
            payload={"ok":False,"error":"READ_FAILED","detail":str(e)[:200],"rid_req":rid_req,"rid_used":rid_req,"from":f"{rid_req}/{rel_used}","data":None}
            start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store")],None)
            return [ _vsp_json_rfa2.dumps(payload,ensure_ascii=False).encode("utf-8") ]

        # limit
        try:
            lim=int(limit_s) if limit_s else 0
        except Exception:
            lim=0
        if lim and isinstance(data, dict) and isinstance(data.get("findings"), list):
            data=dict(data)
            data["findings"]=data["findings"][:max(0,lim)]

        payload={"ok":True,"rid_req":rid_req,"rid_used":rid_req,"from":f"{rid_req}/{rel_used}","data":data}
        start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store")],None)
        return [ _vsp_json_rfa2.dumps(payload,ensure_ascii=False).encode("utf-8") ]

try:
    application = _VspRunFileAllowStrictPerRidMwV2(application)
except Exception:
    pass
# --- /VSP_P0_RUN_FILE_ALLOW_STRICT_PER_RID_V2_BASESCAN ---
# VSP_P0_RUN_FILE_ALLOW_STRICT_PER_RID_V2_BASESCAN
'''
s = s.rstrip() + "\n\n" + block + "\n# " + MARK + "\n"
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended V2 strict resolver MW + py_compile OK")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "systemctl restart failed"
  sleep 0.7
fi

echo "== [VERIFY] expect ok=True for at least one real RID =="
for RID in "$RID_A" "$RID_B"; do
  echo "-- $RID --"
  curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"error=",j.get("error"),"from=",j.get("from"),"has_data=",isinstance(j.get("data"),dict))'
done

ok "DONE"
