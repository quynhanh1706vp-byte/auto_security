#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"
LOG="$ROOT/out_ci/ui_8910.log"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_runapi_fallback_${TS}"
echo "[BACKUP] $APP.bak_runapi_fallback_${TS}"

python3 - "$APP" << 'PY'
import re, sys, time
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_RUN_API_FALLBACK_V1" in txt:
    print("[SKIP] already has VSP_RUN_API_FALLBACK_V1")
    raise SystemExit(0)

# Find app var name
m = re.search(r"^\s*(\w+)\s*=\s*Flask\s*\(", txt, flags=re.M)
appvar = m.group(1) if m else "app"

block = f'''
# === VSP_RUN_API_FALLBACK_V1 ===
# If real run_api blueprint fails to load, we still MUST expose /api/vsp/run_v1 and /api/vsp/run_status_v1/*
# so UI + jq never breaks. This is the "commercial contract".
def _vsp_env_int(name, default):
    try:
        import os
        v = os.getenv(name, "")
        if str(v).strip() == "":
            return int(default)
        return int(float(v))
    except Exception:
        return int(default)

def _vsp_contractize(payload):
    if not isinstance(payload, dict):
        payload = {{"ok": False, "status": "ERROR", "final": True, "error": "INVALID_STATUS_PAYLOAD"}}
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
    payload.setdefault("killed", bool(payload.get("killed", False)))
    payload.setdefault("kill_reason", payload.get("kill_reason") or "")
    payload.setdefault("progress_pct", int(payload.get("progress_pct") or 0))
    payload.setdefault("stage_index", int(payload.get("stage_index") or 0))
    payload.setdefault("stage_total", int(payload.get("stage_total") or 0))
    payload.setdefault("stage_name", payload.get("stage_name") or "")
    payload.setdefault("stage_sig", payload.get("stage_sig") or "")
    payload.setdefault("updated_at", int(__import__("time").time()))
    return payload

try:
    bp_vsp_run_api_v1  # noqa
except Exception:
    bp_vsp_run_api_v1 = None

if bp_vsp_run_api_v1 is None:
    from flask import Blueprint, request, jsonify
    bp_vsp_run_api_v1 = Blueprint("vsp_run_api_v1_fallback", __name__)
    _VSP_FALLBACK_REQ = {{}}

    @bp_vsp_run_api_v1.route("/api/vsp/run_v1", methods=["POST"])
    def _fallback_run_v1():
        # Keep same behavior: missing body => 400 but still JSON
        body = None
        try:
            body = request.get_json(silent=True)
        except Exception:
            body = None
        if not body:
            return jsonify({{"ok": False, "error": "MISSING_BODY"}}), 400

        req_id = "REQ_FALLBACK_" + __import__("time").strftime("%Y%m%d_%H%M%S")
        st = _vsp_contractize({{
            "ok": True,
            "status": "RUNNING",
            "final": False,
            "error": "",
            "req_id": req_id,
            "progress_pct": 0,
            "stage_index": 0,
            "stage_total": 0,
            "stage_name": "INIT",
            "stage_sig": "0/0|INIT|0",
        }})
        _VSP_FALLBACK_REQ[req_id] = st
        return jsonify({{"ok": True, "request_id": req_id, "implemented": False, "message": "Fallback run_api active (real bp load failed)."}}), 200

    @bp_vsp_run_api_v1.route("/api/vsp/run_status_v1/<req_id>", methods=["GET"])
    def _fallback_run_status_v1(req_id):
        if req_id not in _VSP_FALLBACK_REQ:
            return jsonify(_vsp_contractize({{
                "ok": False,
                "status": "NOT_FOUND",
                "final": True,
                "error": "REQ_ID_NOT_FOUND",
                "req_id": req_id
            }})), 200
        return jsonify(_vsp_contractize(_VSP_FALLBACK_REQ[req_id])), 200

    try:
        {appvar}.register_blueprint(bp_vsp_run_api_v1)
        print("[VSP_RUN_API_FALLBACK] mounted /api/vsp/run_v1 + /api/vsp/run_status_v1/*")
    except Exception as e:
        print("[VSP_RUN_API_FALLBACK] mount failed:", repr(e))
# === END VSP_RUN_API_FALLBACK_V1 ===
'''

# Insert BEFORE __main__ guard if present, else append end.
mm = re.search(r"^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:\s*$", txt, flags=re.M)
if mm:
    txt2 = txt[:mm.start()] + block + "\n" + txt[mm.start():]
else:
    txt2 = txt + "\n" + block + "\n"

p.write_text(txt2, encoding="utf-8")
print("[OK] inserted VSP_RUN_API_FALLBACK_V1")
PY

python3 -m py_compile vsp_demo_app.py >/dev/null 2>&1 || { echo "[ERR] py_compile failed"; exit 2; }
echo "[OK] py_compile OK"

pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > "$LOG" 2>&1 &
sleep 1

echo "== Smoke 1: run_status fake must be NOT_FOUND (not 404) =="
python3 - <<'PY'
import json, urllib.request
u="http://localhost:8910/api/vsp/run_status_v1/FAKE_REQ_ID"
obj=json.loads(urllib.request.urlopen(u,timeout=5).read().decode("utf-8","ignore"))
keys=["ok","status","final","error","stall_timeout_sec","total_timeout_sec","progress_pct","stage_index","stage_total","stage_name","stage_sig"]
print({k:obj.get(k) for k in keys})
PY

echo "== Smoke 2: run_v1 missing body must be HTTP 400 JSON =="
curl -sS -o /tmp/vsp_runv1_body.txt -w "HTTP=%{http_code}\n" -X POST "http://localhost:8910/api/vsp/run_v1" || true
head -c 200 /tmp/vsp_runv1_body.txt; echo

echo "== Log tail =="
tail -n 60 "$LOG" || true
echo "[DONE]"
