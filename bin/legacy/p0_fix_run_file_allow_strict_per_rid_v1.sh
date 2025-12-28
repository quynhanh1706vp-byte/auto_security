#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need head
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID1="${1:-VSP_CI_20251215_173713}"
RID2="${2:-VSP_CI_20251211_133204}"

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P0_RUN_FILE_ALLOW_STRICT_PER_RID_V1"
cp -f "$WSGI" "${WSGI}.bak_${MARK}_${TS}"
ok "backup: ${WSGI}.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_P0_RUN_FILE_ALLOW_STRICT_PER_RID_V1"
if MARK in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

block = r'''
# --- VSP_P0_RUN_FILE_ALLOW_STRICT_PER_RID_V1 ---
# Commercial guarantee:
# - If rid is provided, MUST resolve files from that rid's run_dir only.
# - NEVER silently fallback to rid_latest for a non-empty rid.
# - Return wrapper: {ok, rid_req, rid_used, from, data|error}
import os as _vsp_os_rfa
import json as _vsp_json_rfa
import urllib.parse as _vsp_urlparse_rfa

def _vsp_rfa_json(status: str, headers: list, payload: dict):
    body=_vsp_json_rfa.dumps(payload, ensure_ascii=False).encode("utf-8")
    # strip Content-Length to recalc
    new_headers=[(k,v) for (k,v) in (headers or []) if (k or "").lower()!="content-length"]
    new_headers.append(("Content-Type","application/json; charset=utf-8"))
    new_headers.append(("Cache-Control","no-store"))
    new_headers.append(("Content-Length", str(len(body))))
    return status, new_headers, [body]

def _vsp_rfa_safe_relpath(path: str) -> str:
    path=(path or "").strip()
    if not path or path.startswith("/") or "\x00" in path:
        return ""
    # block traversal
    parts=[p for p in path.split("/") if p not in ("", ".")]
    if any(p==".." for p in parts):
        return ""
    return "/".join(parts)

def _vsp_rfa_guess_roots():
    roots=[]
    for env in ("VSP_RUNS_ROOT","VSP_RUN_ROOT","VSP_OUT_CI_ROOT","VSP_OUT_ROOT"):
        v=_vsp_os_rfa.environ.get(env)
        if v and _vsp_os_rfa.path.isdir(v):
            roots.append(v)
    # defaults for this repo
    for d in (
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",   # sometimes ui writes here
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ):
        if _vsp_os_rfa.path.isdir(d) and d not in roots:
            roots.append(d)
    return roots

def _vsp_rfa_find_run_dir(rid: str):
    for root in _vsp_rfa_guess_roots():
        cand=_vsp_os_rfa.path.join(root, rid)
        if _vsp_os_rfa.path.isdir(cand):
            return cand
    return None

def _vsp_rfa_resolve_file(run_dir: str, rel: str):
    # allow alias mapping for common layouts
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
        fp=_vsp_os_rfa.path.join(run_dir, r)
        if _vsp_os_rfa.path.isfile(fp):
            return fp, r
    return None, None

class _VspRunFileAllowStrictPerRidMw:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path != "/api/vsp/run_file_allow":
            return self.app(environ, start_response)

        qs=_vsp_urlparse_rfa.parse_qs(environ.get("QUERY_STRING",""))
        rid_req=(qs.get("rid",[""])[0] or "").strip()
        req_path=(qs.get("path",[""])[0] or "").strip()
        limit_s=(qs.get("limit",[""])[0] or "").strip()

        # rid is required for commercial correctness (no guessing)
        if not rid_req:
            status, headers, body = _vsp_rfa_json("200 OK", [], {
                "ok": False,
                "error": "RID_REQUIRED",
                "rid_req": rid_req,
                "rid_used": "",
                "from": "",
            })
            start_response(status, headers, None)
            return body

        rel=_vsp_rfa_safe_relpath(req_path)
        if not rel:
            status, headers, body = _vsp_rfa_json("200 OK", [], {
                "ok": False,
                "error": "INVALID_PATH",
                "rid_req": rid_req,
                "rid_used": rid_req,
                "from": "",
            })
            start_response(status, headers, None)
            return body

        run_dir=_vsp_rfa_find_run_dir(rid_req)
        if not run_dir:
            status, headers, body = _vsp_rfa_json("200 OK", [], {
                "ok": False,
                "error": "RID_NOT_FOUND",
                "rid_req": rid_req,
                "rid_used": rid_req,
                "from": "",
            })
            start_response(status, headers, None)
            return body

        fp, rel_used=_vsp_rfa_resolve_file(run_dir, rel)
        if not fp:
            status, headers, body = _vsp_rfa_json("200 OK", [], {
                "ok": False,
                "error": "FILE_NOT_FOUND",
                "rid_req": rid_req,
                "rid_used": rid_req,
                "from": f"{rid_req}/{rel}",
            })
            start_response(status, headers, None)
            return body

        # load JSON
        try:
            with open(fp, "rb") as f:
                raw=f.read()
            try:
                data=_vsp_json_rfa.loads(raw.decode("utf-8","ignore") or "{}")
            except Exception:
                data={"_raw_text": raw.decode("utf-8","ignore")}
        except Exception as e:
            status, headers, body = _vsp_rfa_json("200 OK", [], {
                "ok": False,
                "error": "READ_FAILED",
                "detail": str(e)[:200],
                "rid_req": rid_req,
                "rid_used": rid_req,
                "from": f"{rid_req}/{rel_used}",
            })
            start_response(status, headers, None)
            return body

        # apply limit for findings_unified-like payload
        try:
            lim=int(limit_s) if limit_s else 0
        except Exception:
            lim=0

        if lim and isinstance(data, dict) and isinstance(data.get("findings"), list):
            data = dict(data)
            data["findings"] = data["findings"][:max(0, lim)]

        payload = {
            "ok": True,
            "rid_req": rid_req,
            "rid_used": rid_req,
            # IMPORTANT: include rid to make alias audits obvious
            "from": f"{rid_req}/{rel_used}",
            "data": data,
        }
        status, headers, body = _vsp_rfa_json("200 OK", [], payload)
        start_response(status, headers, None)
        return body

try:
    application = _VspRunFileAllowStrictPerRidMw(application)
except Exception:
    pass
# --- /VSP_P0_RUN_FILE_ALLOW_STRICT_PER_RID_V1 ---
# VSP_P0_RUN_FILE_ALLOW_STRICT_PER_RID_V1
'''
s = s.rstrip() + "\n\n" + block + "\n# " + MARK + "\n"
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended strict run_file_allow MW + py_compile OK")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "systemctl restart failed"
  sleep 0.7
fi

echo "== [VERIFY] run_file_allow wrapper + from includes rid =="
for RID in "$RID1" "$RID2"; do
  echo "-- $RID --"
  curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid_used=",j.get("rid_used"),"from=",j.get("from"),"has_data=",isinstance(j.get("data"),dict))'
done

echo "== [VERIFY] RID_NOT_FOUND behavior =="
curl -fsS "$BASE/api/vsp/run_file_allow?rid=RID_DOES_NOT_EXIST_123&path=run_gate_summary.json" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"error=",j.get("error"))'

ok "DONE"
