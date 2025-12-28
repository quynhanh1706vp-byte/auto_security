#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_routes_v2_${TS}"
echo "[BACKUP] $F.bak_export_routes_v2_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

start = txt.find("# === VSP_EXPORT_CONTRACT_ROUTES_V1 ===")
end = txt.find("# === END VSP_EXPORT_CONTRACT_ROUTES_V1 ===")
if start == -1 or end == -1:
    print("[ERR] cannot find VSP_EXPORT_CONTRACT_ROUTES_V1 block to replace")
    raise SystemExit(2)
end = end + len("# === END VSP_EXPORT_CONTRACT_ROUTES_V1 ===")

new_block = r'''
# === VSP_EXPORT_CONTRACT_ROUTES_V1 ===
# Ensure commercial contract URLs exist AND always return contract fields.
try:
    _bp = bp_vsp_run_api_v1
except Exception:
    _bp = None

# Prefer existing normalizer if present; else provide local one.
try:
    _normalize = _vsp_contract_normalize_status
except Exception:
    def _vsp_env_int(name, default):
        try:
            import os
            v = os.getenv(name, "")
            if str(v).strip() == "":
                return int(default)
            return int(float(v))
        except Exception:
            return int(default)

    def _normalize(payload):
        if not isinstance(payload, dict):
            payload = {"ok": False, "status": "ERROR", "final": True, "error": "INVALID_STATUS_PAYLOAD"}
        stall = _vsp_env_int("VSP_UIREQ_STALL_TIMEOUT_SEC", _vsp_env_int("VSP_STALL_TIMEOUT_SEC", 600))
        total = _vsp_env_int("VSP_UIREQ_TOTAL_TIMEOUT_SEC", _vsp_env_int("VSP_TOTAL_TIMEOUT_SEC", 7200))
        if stall < 1: stall = 1
        if total < 1: total = 1
        payload.setdefault("ok", bool(payload.get("ok", False)))
        payload.setdefault("status", payload.get("status") or "UNKNOWN")
        payload.setdefault("final", bool(payload.get("final", False)))
        payload.setdefault("error", payload.get("error") or "")
        payload.setdefault("req_id", payload.get("req_id") or "")
        payload["stall_timeout_sec"] = int(payload.get("stall_timeout_sec") or stall)
        payload["total_timeout_sec"] = int(payload.get("total_timeout_sec") or total)
        payload.setdefault("progress_pct", int(payload.get("progress_pct") or 0))
        payload.setdefault("stage_index", int(payload.get("stage_index") or 0))
        payload.setdefault("stage_total", int(payload.get("stage_total") or 0))
        payload.setdefault("stage_name", payload.get("stage_name") or "")
        payload.setdefault("stage_sig", payload.get("stage_sig") or "")
        payload.setdefault("updated_at", int(__import__("time").time()))
        return payload

def _export_run_status_v1(req_id):
    # Call original handler (if exists), then normalize JSON payload.
    from flask import jsonify
    resp = run_status_v1(req_id)
    code = 200
    headers = None

    if isinstance(resp, tuple):
        # (response, code) or (response, code, headers)
        if len(resp) >= 2:
            code = resp[1]
        if len(resp) >= 3:
            headers = resp[2]
        resp = resp[0]

    data = None
    try:
        data = resp.get_json(silent=True)
    except Exception:
        data = None

    out = _normalize(data or {"ok": False, "status": "ERROR", "final": True, "error": "NON_JSON_RESPONSE", "req_id": req_id})
    if headers is not None:
        return jsonify(out), code, headers
    return jsonify(out), code

def _try_add(rule, view_func, methods, endpoint):
    try:
        if _bp is None or view_func is None:
            return
        _bp.add_url_rule(rule, endpoint=endpoint, view_func=view_func, methods=methods)
    except Exception:
        # ignore duplicates/assertions
        pass

# keep run_v1 export as-is (no need to normalize)
_try_add("/api/vsp/run_v1", globals().get("run_v1"), ["POST"], "run_v1_export_v1")
# contractize status export
_try_add("/api/vsp/run_status_v1/<req_id>", _export_run_status_v1, ["GET"], "run_status_v1_export_v1")
# === END VSP_EXPORT_CONTRACT_ROUTES_V1 ===
'''.strip("\n")

txt2 = txt[:start] + new_block + "\n" + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] replaced VSP_EXPORT_CONTRACT_ROUTES_V1 with contractizing wrapper")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

# restart with fallback disabled
pkill -f vsp_demo_app.py || true
VSP_DISABLE_RUNAPI_FALLBACK=1 nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== Smoke: run_status_v1 fake must have non-None timeouts =="
python3 - <<'PY'
import json, urllib.request
u="http://localhost:8910/api/vsp/run_status_v1/FAKE_REQ_ID"
obj=json.loads(urllib.request.urlopen(u,timeout=5).read().decode("utf-8","ignore"))
keys=["ok","status","final","error","stall_timeout_sec","total_timeout_sec","progress_pct","stage_index","stage_total"]
print({k: obj.get(k) for k in keys})
PY

echo "== Quick urlmap check (optional) =="
python3 - <<'PY'
import flask, vsp_demo_app as mod
app=None
for k,v in vars(mod).items():
    if isinstance(v, flask.Flask):
        app=v; break
print("has /api/vsp/run_status_v1/<req_id> =", any(r.rule=="/api/vsp/run_status_v1/<req_id>" for r in app.url_map.iter_rules()))
PY

tail -n 40 out_ci/ui_8910.log
echo "[DONE]"
