#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p102_${TS}"
echo "[BACKUP] ${APP}.bak_p102_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P102_PIN_LATEST_CI_FIRSTPAGE_V1"
if marker in s:
    print("[OK] already patched")
    sys.exit(0)

# Require P94 helpers exist
need = ["_vsp_p94_list_runs_dirs", "_vsp_p94_json"]
missing = [x for x in need if x not in s]
if missing:
    print("[ERR] missing prerequisites:", missing)
    sys.exit(2)

addon = r'''
# VSP_P102_PIN_LATEST_CI_FIRSTPAGE_V1
# Goal: always surface newest VSP_CI_* in the first page of /api/ui/runs_v3 (avoid RID mismatch).
try:
    _VSP_P102_CACHE = {"t": 0.0, "key": "", "val": None}
except Exception:
    _VSP_P102_CACHE = None

@app.get("/api/ui/runs_v3_p102")
def vsp_p102_api_ui_runs_v3_debug():
    return vsp_p102_api_ui_runs_v3()

@app.get("/api/ui/runs_v3")
def vsp_p102_api_ui_runs_v3():
    try:
        include_ci = request.args.get("include_ci", "1") in ("1","true","yes","on")
        limit_req = int(request.args.get("limit", "200"))
        limit_req = max(1, min(limit_req, 500))
        key = f"p102&ci={1 if include_ci else 0}&limit={limit_req}"

        import time
        if _VSP_P102_CACHE and _VSP_P102_CACHE.get("val") is not None:
            if (time.time() - float(_VSP_P102_CACHE.get("t", 0.0))) < 15.0 and _VSP_P102_CACHE.get("key")==key:
                return _vsp_p94_json(_VSP_P102_CACHE["val"], 200)

        # Ask for a large list; even if helper slices, this still increases chance to include CI.
        items_all = _vsp_p94_list_runs_dirs(include_ci=include_ci, limit=10000)

        # Pin newest VSP_CI_ to the top if present (helper sorts by ts desc already).
        items = items_all
        if include_ci:
            vsp_ci = [x for x in items_all if str(x.get("rid","")).startswith("VSP_CI_")]
            if vsp_ci:
                newest_ci = vsp_ci[0]
                rest = [x for x in items_all if x is not newest_ci]
                items = [newest_ci] + rest

        items = items[:limit_req]

        out = {
            "ok": True,
            "ver": "p102",
            "include_ci": include_ci,
            "total": len(items),
            "items": items,
            "runs": items,
        }
        if _VSP_P102_CACHE is not None:
            _VSP_P102_CACHE["t"] = time.time()
            _VSP_P102_CACHE["key"] = key
            _VSP_P102_CACHE["val"] = out
        return _vsp_p94_json(out, 200)
    except Exception as e:
        return _vsp_p94_json({"ok": False, "ver":"p102", "err": str(e)}, 500)

# Force-map any existing /api/ui/runs_v3 endpoints to our p102 handler (route conflicts safe)
try:
    _fn = globals().get("vsp_p102_api_ui_runs_v3")
    if _fn:
        for _r in list(app.url_map.iter_rules()):
            if _r.rule == "/api/ui/runs_v3" and ("GET" in getattr(_r, "methods", set())):
                try:
                    app.view_functions[_r.endpoint] = _fn
                except Exception:
                    pass
except Exception:
    pass
'''
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended P102 pin CI + override /api/ui/runs_v3")
PY

echo "== [P102] py_compile =="
python3 -m py_compile "$APP"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [P102] daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== [P102] wait HTTP up (/runs) =="
ok=0
for i in $(seq 1 120); do
  if curl -fsS --connect-timeout 1 --max-time 3 "$BASE/runs" -o /dev/null; then ok=1; break; fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] HTTP not reachable"; exit 2; }

echo "== [P102] smoke runs_v3 has VSP_CI in first page =="
curl -fsS "$BASE/api/ui/runs_v3?limit=50&include_ci=1" -o /tmp/p102_runs_v3.json
python3 - <<'PY'
import json
s=open("/tmp/p102_runs_v3.json","r",encoding="utf-8",errors="replace").read()
j=json.loads(s)
txt=str(j)
print("ok=", j.get("ok"), "ver=", j.get("ver"), "items=", len(j.get("items",[])), "has_VSP_CI=", ("VSP_CI_" in txt))
PY

echo "[OK] P102 done"
