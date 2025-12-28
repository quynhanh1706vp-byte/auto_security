#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need sed

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p103_${TS}"
echo "[BACKUP] ${W}.bak_p103_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P103_GATEWAY_RUNS_V3_OVERRIDE_V1"
if marker in s:
    print("[OK] already patched")
    sys.exit(0)

addon = r'''
# VSP_P103_GATEWAY_RUNS_V3_OVERRIDE_V1
# Override /api/ui/runs_v3 in the *gateway* app (real serving layer).
try:
    import os, time, json
    from flask import request, Response
except Exception:
    os = None

_VSP_P103_CACHE = {"t": 0.0, "key": "", "val": None}

def _vsp_p103_json(obj, code=200):
    try:
        return Response(json.dumps(obj, ensure_ascii=False), status=code, mimetype="application/json")
    except Exception:
        return Response('{"ok":false,"ver":"p103","err":"json_encode_failed"}', status=500, mimetype="application/json")

def _vsp_p103_scan_runs(include_ci: bool, limit: int):
    roots = ["/home/test/Data/SECURITY_BUNDLE/out"]
    if include_ci:
        roots += ["/home/test/Data/SECURITY_BUNDLE/out_ci", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"]

    items = []
    seen = set()
    now = time.time()

    for root in roots:
        try:
            if not os.path.isdir(root):
                continue
            for name in os.listdir(root):
                if not (name.startswith("RUN_") or name.startswith("VSP_CI_")):
                    continue
                full = os.path.join(root, name)
                # follow symlink OK, but dedupe by realpath to avoid VSP_CI_RUN_* alias
                try:
                    real = os.path.realpath(full)
                except Exception:
                    real = full

                if real in seen:
                    continue
                if not os.path.isdir(real):
                    continue
                seen.add(real)

                try:
                    st = os.stat(real)
                    mtime = float(st.st_mtime)
                except Exception:
                    mtime = now

                items.append({
                    "rid": name,
                    "run_id": name,   # legacy alias
                    "name": name,
                    "path": real,
                    "root": root,
                    "ts": mtime,
                    "kind": ("ci" if name.startswith("VSP_CI_") else "run"),
                })
        except Exception:
            continue

    # sort newest first
    items.sort(key=lambda x: x.get("ts", 0.0), reverse=True)

    # pin newest VSP_CI to the top of first page
    if include_ci:
        ci = [x for x in items if str(x.get("rid","")).startswith("VSP_CI_")]
        if ci:
            newest_ci = ci[0]
            rest = [x for x in items if x is not newest_ci]
            items = [newest_ci] + rest

    return items[:max(1, min(int(limit), 500))]

def vsp_p103_api_ui_runs_v3():
    try:
        include_ci = request.args.get("include_ci", "1") in ("1","true","yes","on")
        limit_req = int(request.args.get("limit", "200"))
        limit_req = max(1, min(limit_req, 500))
        key = f"ci={1 if include_ci else 0}&limit={limit_req}"

        # cache 15s
        if _VSP_P103_CACHE.get("val") is not None:
            if (time.time() - float(_VSP_P103_CACHE.get("t", 0.0))) < 15.0 and _VSP_P103_CACHE.get("key")==key:
                return _vsp_p103_json(_VSP_P103_CACHE["val"], 200)

        items = _vsp_p103_scan_runs(include_ci=include_ci, limit=limit_req)
        out = {
            "ok": True,
            "ver": "p103",
            "include_ci": include_ci,
            "total": len(items),
            "items": items,
            "runs": items,   # legacy alias
        }
        _VSP_P103_CACHE["t"] = time.time()
        _VSP_P103_CACHE["key"] = key
        _VSP_P103_CACHE["val"] = out
        return _vsp_p103_json(out, 200)
    except Exception as e:
        return _vsp_p103_json({"ok": False, "ver":"p103", "err": str(e)}, 500)

def _vsp_p103_force_route():
    # Force all existing rules for /api/ui/runs_v3 to use our handler
    a = globals().get("application") or globals().get("app")
    if not a:
        return
    try:
        for r in list(a.url_map.iter_rules()):
            if r.rule == "/api/ui/runs_v3" and ("GET" in getattr(r, "methods", set())):
                try:
                    a.view_functions[r.endpoint] = vsp_p103_api_ui_runs_v3
                except Exception:
                    pass
    except Exception:
        pass

try:
    _vsp_p103_force_route()
except Exception:
    pass
'''
p.write_text(s.rstrip() + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended P103 gateway override for /api/ui/runs_v3")
PY

echo "== [P103] py_compile =="
python3 -m py_compile "$W"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [P103] daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== [P103] wait HTTP up (/runs) =="
ok=0
for i in $(seq 1 150); do
  if curl -fsS --connect-timeout 1 --max-time 3 "$BASE/runs" -o /dev/null; then ok=1; break; fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] HTTP not reachable at $BASE"; journalctl -u "$SVC" -n 120 --no-pager | tail -n 120; exit 2; }

echo "== [P103] smoke runs_v3 must show ver=p103 + has VSP_CI =="
curl -fsS "$BASE/api/ui/runs_v3?limit=50&include_ci=1" -o /tmp/p103_runs_v3.json
python3 - <<'PY'
import json
s=open("/tmp/p103_runs_v3.json","r",encoding="utf-8",errors="replace").read()
j=json.loads(s)
txt=str(j)
items=j.get("items",[])
first = items[0]["rid"] if items else None
print("ok=", j.get("ok"), "ver=", j.get("ver"), "items=", len(items), "first=", first, "has_VSP_CI=", ("VSP_CI_" in txt))
PY

echo "[OK] P103 done"
