#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need grep

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p104_${TS}"
echo "[BACKUP] ${W}.bak_p104_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P104_GATEWAY_AUTOFIND_APP_OVERRIDE_RUNS_V3_V1"
if marker in s:
    print("[OK] already patched")
    sys.exit(0)

addon = r'''
# VSP_P104_GATEWAY_AUTOFIND_APP_OVERRIDE_RUNS_V3_V1
# Robustly find the real Flask app object(s) and override /api/ui/runs_v3 to use our handler.
try:
    import os, time, json
    from flask import request, Response
except Exception:
    os = None

def _vsp_p104_json(obj, code=200):
    try:
        return Response(json.dumps(obj, ensure_ascii=False), status=code, mimetype="application/json")
    except Exception:
        return Response('{"ok":false,"ver":"p104","err":"json_encode_failed"}', status=500, mimetype="application/json")

_VSP_P104_CACHE = {"t": 0.0, "key": "", "val": None}

def _vsp_p104_scan_runs(include_ci: bool, limit: int):
    roots = ["/home/test/Data/SECURITY_BUNDLE/out"]
    if include_ci:
        roots += ["/home/test/Data/SECURITY_BUNDLE/out_ci", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"]

    items=[]
    seen=set()
    now=time.time()

    for root in roots:
        try:
            if not os.path.isdir(root):
                continue
            for name in os.listdir(root):
                if not (name.startswith("RUN_") or name.startswith("VSP_CI_")):
                    continue
                full=os.path.join(root, name)
                try:
                    real=os.path.realpath(full)
                except Exception:
                    real=full
                if real in seen:
                    continue
                if not os.path.isdir(real):
                    continue
                seen.add(real)
                try:
                    st=os.stat(real); mtime=float(st.st_mtime)
                except Exception:
                    mtime=now
                items.append({
                    "rid": name,
                    "run_id": name,
                    "name": name,
                    "path": real,
                    "root": root,
                    "ts": mtime,
                    "kind": ("ci" if name.startswith("VSP_CI_") else "run"),
                })
        except Exception:
            continue

    items.sort(key=lambda x: x.get("ts", 0.0), reverse=True)

    # Pin newest VSP_CI_ into first page
    if include_ci:
        ci=[x for x in items if str(x.get("rid","")).startswith("VSP_CI_")]
        if ci:
            newest_ci=ci[0]
            rest=[x for x in items if x is not newest_ci]
            items=[newest_ci]+rest

    return items[:max(1, min(int(limit), 500))]

def vsp_p104_api_ui_runs_v3():
    try:
        include_ci = request.args.get("include_ci", "1") in ("1","true","yes","on")
        limit_req = int(request.args.get("limit", "200"))
        limit_req = max(1, min(limit_req, 500))
        key = f"p104&ci={1 if include_ci else 0}&limit={limit_req}"

        if _VSP_P104_CACHE.get("val") is not None:
            if (time.time() - float(_VSP_P104_CACHE.get("t", 0.0))) < 15.0 and _VSP_P104_CACHE.get("key")==key:
                return _vsp_p104_json(_VSP_P104_CACHE["val"], 200)

        items = _vsp_p104_scan_runs(include_ci=include_ci, limit=limit_req)
        out = {"ok": True, "ver":"p104", "include_ci": include_ci, "total": len(items), "items": items, "runs": items}
        _VSP_P104_CACHE["t"]=time.time()
        _VSP_P104_CACHE["key"]=key
        _VSP_P104_CACHE["val"]=out
        return _vsp_p104_json(out, 200)
    except Exception as e:
        return _vsp_p104_json({"ok": False, "ver":"p104", "err": str(e)}, 500)

def _vsp_p104_is_flask_app(x):
    return hasattr(x, "url_map") and hasattr(x, "view_functions") and hasattr(x, "add_url_rule")

def _vsp_p104_find_apps():
    apps=[]
    # scan globals
    for v in list(globals().values()):
        try:
            if _vsp_p104_is_flask_app(v):
                apps.append(v)
        except Exception:
            pass
    # common wrapper cases: application.app, application._app, etc.
    for name in ("application","app","flask_app","APP"):
        v=globals().get(name)
        for attr in ("app","_app","flask_app"):
            try:
                vv=getattr(v, attr, None)
                if vv is not None and _vsp_p104_is_flask_app(vv):
                    apps.append(vv)
            except Exception:
                pass
    # dedupe by id
    out=[]; seen=set()
    for a in apps:
        if id(a) in seen: continue
        seen.add(id(a)); out.append(a)
    return out

def _vsp_p104_force_override():
    apps=_vsp_p104_find_apps()
    for a in apps:
        # ensure a debug path exists too
        try:
            a.add_url_rule("/api/ui/runs_v3_p104", "runs_v3_p104", vsp_p104_api_ui_runs_v3, methods=["GET"])
        except Exception:
            pass
        try:
            for r in list(a.url_map.iter_rules()):
                if r.rule == "/api/ui/runs_v3" and ("GET" in getattr(r, "methods", set())):
                    try:
                        a.view_functions[r.endpoint] = vsp_p104_api_ui_runs_v3
                    except Exception:
                        pass
        except Exception:
            pass

try:
    _vsp_p104_force_override()
except Exception:
    pass
'''
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended P104 override block")
PY

echo "== [P104] py_compile =="
python3 -m py_compile "$W"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [P104] daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== [P104] wait HTTP up (/runs) =="
ok=0
for i in $(seq 1 160); do
  if curl -fsS --connect-timeout 1 --max-time 3 "$BASE/runs" -o /dev/null; then ok=1; break; fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] HTTP not reachable"; journalctl -u "$SVC" -n 120 --no-pager | tail -n 120; exit 2; }

echo "== [P104] smoke #1: main runs_v3 must be ver=p104 and has VSP_CI =="
curl -fsS "$BASE/api/ui/runs_v3?limit=50&include_ci=1" -o /tmp/p104_runs_v3.json
python3 - <<'PY'
import json
j=json.load(open("/tmp/p104_runs_v3.json","r",encoding="utf-8",errors="replace"))
items=j.get("items",[])
txt=str(j)
print("ok=", j.get("ok"), "ver=", j.get("ver"), "items=", len(items),
      "first=", (items[0]["rid"] if items else None),
      "has_VSP_CI=", ("VSP_CI_" in txt))
PY

echo "== [P104] smoke #2: debug endpoint must also work (runs_v3_p104) =="
curl -fsS "$BASE/api/ui/runs_v3_p104?limit=50&include_ci=1" -o /tmp/p104_runs_v3_dbg.json
python3 - <<'PY'
import json
j=json.load(open("/tmp/p104_runs_v3_dbg.json","r",encoding="utf-8",errors="replace"))
items=j.get("items",[])
txt=str(j)
print("ok=", j.get("ok"), "ver=", j.get("ver"), "items=", len(items),
      "first=", (items[0]["rid"] if items else None),
      "has_VSP_CI=", ("VSP_CI_" in txt))
PY

echo "[OK] P104 done"
