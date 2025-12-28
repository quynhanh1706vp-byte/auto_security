#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_routes_${TS}"
echo "[BACKUP] $F.bak_export_routes_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")
if "VSP_EXPORT_CONTRACT_ROUTES_V1" in txt:
    print("[SKIP] already patched")
    raise SystemExit(0)

block = r'''
# === VSP_EXPORT_CONTRACT_ROUTES_V1 ===
# Ensure commercial contract URLs exist even if original routes used different prefixes.
try:
    _bp = bp_vsp_run_api_v1
except Exception:
    _bp = None

def _try_add(rule, view_name, methods, endpoint):
    try:
        fn = globals().get(view_name)
        if _bp is None or fn is None:
            return
        _bp.add_url_rule(rule, endpoint=endpoint, view_func=fn, methods=methods)
    except Exception:
        # ignore duplicates or any assertion errors
        pass

_try_add("/api/vsp/run_v1", "run_v1", ["POST"], "run_v1_export_v1")
_try_add("/api/vsp/run_status_v1/<req_id>", "run_status_v1", ["GET"], "run_status_v1_export_v1")
# === END VSP_EXPORT_CONTRACT_ROUTES_V1 ===
'''
p.write_text(txt + "\n" + block + "\n", encoding="utf-8")
print("[OK] appended VSP_EXPORT_CONTRACT_ROUTES_V1")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

# restart with fallback disabled
pkill -f vsp_demo_app.py || true
VSP_DISABLE_RUNAPI_FALLBACK=1 nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== Smoke: must be NOT_FOUND (not 404) =="
python3 - <<'PY'
import json, urllib.request
u="http://localhost:8910/api/vsp/run_status_v1/FAKE_REQ_ID"
obj=json.loads(urllib.request.urlopen(u,timeout=5).read().decode("utf-8","ignore"))
print({k: obj.get(k) for k in ["ok","status","final","error","stall_timeout_sec","total_timeout_sec"]})
PY

echo "== Log last 40 =="
tail -n 40 out_ci/ui_8910.log
