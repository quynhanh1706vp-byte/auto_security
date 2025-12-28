#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runfile2_${TS}"
echo "[BACKUP] ${F}.bak_runfile2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_RUN_FILE2_SAFE_ENDPOINT_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
else:
    inject = r'''

# =========================
# VSP_RUN_FILE2_SAFE_ENDPOINT_P0_V1
# - New endpoint /api/vsp/run_file2 to avoid collision with existing /api/vsp/run_file
# - Rewrite /api/vsp/runs has.*_path to use run_file2 (safe, no abs path)
# =========================
from pathlib import Path as _P2
from urllib.parse import quote as _q2
import os as _os2
import json as _json2
import mimetypes as _mt2
import re as _re2

try:
    from flask import request as _rq2, send_file as _sf2, Response as _R2
except Exception:
    _rq2 = None  # type: ignore

_VSP_RF2_ALLOWED = {
    "reports/index.html": [
        "reports/index.html","report/index.html","reports/report.html","report/report.html","report.html",
    ],
    "reports/findings_unified.json": [
        "reports/findings_unified.json","report/findings_unified.json","findings_unified.json",
        "reports/unified/findings_unified.json","unified/findings_unified.json",
    ],
    "reports/findings_unified.csv": [
        "reports/findings_unified.csv","report/findings_unified.csv","findings_unified.csv",
        "reports/unified/findings_unified.csv","unified/findings_unified.csv",
    ],
    "reports/findings_unified.sarif": [
        "reports/findings_unified.sarif","report/findings_unified.sarif","findings_unified.sarif",
        "reports/unified/findings_unified.sarif","unified/findings_unified.sarif",
    ],
    "reports/run_gate_summary.json": [
        "reports/run_gate_summary.json","report/run_gate_summary.json","run_gate_summary.json",
        "reports/unified/run_gate_summary.json","unified/run_gate_summary.json",
    ],
}

def _rf2_roots():
    roots=[]
    env=_os2.environ.get("VSP_RUNS_ROOT","").strip()
    if env: roots.append(_P2(env))
    roots += [
        _P2("/home/test/Data/SECURITY_BUNDLE/out"),
        _P2("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        _P2("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        _P2("/home/test/Data/SECURITY-10-10-v4/out_ci"),
    ]
    out=[]; seen=set()
    for r in roots:
        rp=str(r)
        if rp in seen: continue
        seen.add(rp)
        if r.exists(): out.append(r)
    return out

def _rf2_safe_rid(rid:str)->bool:
    return bool(rid) and bool(_re2.fullmatch(r"[A-Za-z0-9_.:-]{6,160}", rid))

def _rf2_find_run_dir(rid:str):
    for root in _rf2_roots():
        for cand in (root/rid, root/"out"/rid):
            if cand.is_dir(): return cand
    return None

def _rf2_pick(run_dir:_P2, vname:str):
    cands=_VSP_RF2_ALLOWED.get(vname)
    if not cands: return None
    rd=run_dir.resolve()
    for rel in cands:
        fp=(run_dir/rel).resolve()
        try:
            if not str(fp).startswith(str(rd)+_os2.sep): 
                continue
            if fp.is_file(): return fp
        except Exception:
            continue
    return None

def _rf2_url(rid:str, vname:str)->str:
    return f"/api/vsp/run_file2?rid={_q2(rid)}&name={_q2(vname)}"

try:
    _app2 = app  # noqa: F821
except Exception:
    _app2 = None

if _app2 is not None and getattr(_app2, "route", None) is not None:
    @_app2.get("/api/vsp/run_file2")
    def _api_vsp_run_file2():
        rid = (_rq2.args.get("rid","") if _rq2 else "").strip()
        name = (_rq2.args.get("name","") if _rq2 else "").strip()
        # allow alias param
        if not name and _rq2:
            name = (_rq2.args.get("path","") or _rq2.args.get("n","") or "").strip()

        if not _rf2_safe_rid(rid):
            return _R2(_json2.dumps({"ok":False,"err":"bad rid"}), status=400, mimetype="application/json")
        if name not in _VSP_RF2_ALLOWED:
            return _R2(_json2.dumps({"ok":False,"err":"not allowed"}), status=404, mimetype="application/json")

        run_dir = _rf2_find_run_dir(rid)
        if not run_dir:
            return _R2(_json2.dumps({"ok":False,"err":"run not found"}), status=404, mimetype="application/json")

        fp = _rf2_pick(run_dir, name)
        if not fp:
            return _R2(_json2.dumps({"ok":False,"err":"file not found"}), status=404, mimetype="application/json")

        ctype,_ = _mt2.guess_type(str(fp))
        ctype = ctype or ("text/html" if str(fp).endswith(".html") else "application/octet-stream")
        as_attach = not (str(fp).endswith(".html") or str(fp).endswith(".json"))
        return _sf2(fp, mimetype=ctype, as_attachment=as_attach, download_name=fp.name)

    @_app2.after_request
    def _rf2_after(resp):
        try:
            if not _rq2 or _rq2.path != "/api/vsp/runs":
                return resp
            if "application/json" not in (resp.headers.get("Content-Type","") or ""):
                return resp
            data = resp.get_json(silent=True)
            if not isinstance(data, dict):
                return resp
            items = data.get("items") or []
            if not isinstance(items, list):
                return resp

            for it in items:
                if not isinstance(it, dict): 
                    continue
                rid = (it.get("run_id") or it.get("rid") or "").strip()
                if not _rf2_safe_rid(rid):
                    continue
                has = it.get("has")
                if not isinstance(has, dict):
                    has = {}
                    it["has"] = has

                rd = _rf2_find_run_dir(rid)
                if not rd:
                    continue

                def mark(vname, flag, keypath):
                    fp = _rf2_pick(rd, vname)
                    if fp:
                        has[flag] = True
                        has[keypath] = _rf2_url(rid, vname)

                # always prefer run_file2 urls
                mark("reports/index.html","html","html_path")
                mark("reports/findings_unified.json","json","json_path")
                mark("reports/findings_unified.csv","csv","csv_path")
                mark("reports/findings_unified.sarif","sarif","sarif_path")
                mark("reports/run_gate_summary.json","summary","summary_path")

                # rewrite any old run_file url -> run_file2
                for k in ("html_path","json_path","csv_path","sarif_path","summary_path"):
                    v = has.get(k)
                    if isinstance(v,str) and v.startswith("/api/vsp/run_file?"):
                        has[k] = v.replace("/api/vsp/run_file?","/api/vsp/run_file2?",1)

            body = _json2.dumps(data, ensure_ascii=False)
            resp.set_data(body)
            resp.headers["Content-Length"] = str(len(body.encode("utf-8")))
            return resp
        except Exception:
            return resp
# =========================
# END VSP_RUN_FILE2_SAFE_ENDPOINT_P0_V1
# =========================
'''
    s = s.rstrip() + "\n" + inject
    p.write_text(s, encoding="utf-8")
    print("[OK] injected:", MARK)

print("[OK] wrote:", p)
PY

echo "== py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart 8910 =="
sudo systemctl restart vsp-ui-8910.service
sleep 0.8

echo "== verify api/vsp/runs path rewrite (limit=5) =="
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=5 | python3 - <<'PY'
import sys,json
d=json.load(sys.stdin)
for it in d.get("items",[]):
  rid=it.get("run_id")
  has=it.get("has") or {}
  if rid:
    print(rid, "json_path=", has.get("json_path"), "html_path=", has.get("html_path"), "summary_path=", has.get("summary_path"))
PY

echo "== smoke run_file2 for one RID having json_path =="
RID="$(curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=50 | python3 - <<'PY'
import sys,json
d=json.load(sys.stdin)
for it in d.get("items",[]):
  has=it.get("has") or {}
  if it.get("run_id") and isinstance(has.get("json_path"),str) and "run_file2" in has["json_path"]:
    print(it["run_id"]); break
PY
)"
echo "[RID]=$RID"
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file2?rid=${RID}&name=reports/findings_unified.json" | sed -n '1,12p'
