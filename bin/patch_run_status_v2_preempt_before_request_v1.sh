#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
LOCK="out_ci/ui_8910.lock"
ts(){ date +%Y%m%d_%H%M%S; }

echo "== [1] backup =="
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
cp -f "$APP" "$APP.bak_preempt_$(ts)"
echo "[BACKUP] $APP.bak_preempt_$(ts)"

echo "== [2] append before_request preempt =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_STATUS_V2_PREEMPT_BEFORE_REQUEST_V1 ==="
if TAG in txt:
    print("[OK] preempt already present, skip")
    raise SystemExit(0)

# Require artifact builder; if missing, abort (you already have it from FORCE_FINAL)
if "_vsp_build_final_status_from_artifacts" not in txt:
    print("[ERR] _vsp_build_final_status_from_artifacts not found. Install FORCE_FINAL block first.")
    raise SystemExit(2)

block = r'''
# === VSP_RUN_STATUS_V2_PREEMPT_BEFORE_REQUEST_V1 ===
try:
    from flask import request as _vsp_req, jsonify as _vsp_jsonify
except Exception:
    _vsp_req = None
    _vsp_jsonify = None

@app.before_request
def _vsp_preempt_run_status_v2():
    # Hard commercial preempt: bypass legacy/wrappers, always serve FINAL-from-artifacts
    if _vsp_req is None or _vsp_jsonify is None:
        return None
    try:
        path = (_vsp_req.path or "")
        if not path.startswith("/api/vsp/run_status_v2/"):
            return None
        rid = path.split("/api/vsp/run_status_v2/", 1)[-1].strip("/")
        data = _vsp_build_final_status_from_artifacts(rid)
        # marker proves preempt executed
        try:
            data["_preempt_before_request_v1"] = True
        except Exception:
            pass
        resp = _vsp_jsonify(data)
        try:
            resp.status_code = int(data.get("http_code") or 200)
        except Exception:
            resp.status_code = 200
        return resp
    except Exception:
        return None
'''

p.write_text(txt + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended before_request preempt")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== [3] restart clean 8910 =="
PIDS="$(ss -lptn 2>/dev/null | awk '/:8910[[:space:]]/ {print $NF}' | sed 's/.*pid=//;s/,.*//' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' || true)"
if [ -n "${PIDS// /}" ]; then
  echo "[KILL] pids: $PIDS"
  for pid in $PIDS; do kill -9 "$pid" 2>/dev/null || true; done
fi
rm -f "$LOCK" 2>/dev/null || true

./bin/restart_8910_gunicorn_commercial_v5.sh || true

echo "== [4] verify (raw + jq) =="
curl -sS http://127.0.0.1:8910/healthz || true
echo

RID="$(curl -sS "http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"

echo "-- RAW (first 300 chars) --"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | head -c 300
echo; echo

echo "-- JSON CHECK --"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{
  ok,http_code,status,error:(.error//null),
  ci_run_dir, overall_verdict,
  has_kics:has("kics_summary"),
  has_semgrep:has("semgrep_summary"),
  has_trivy:has("trivy_summary"),
  has_run_gate:has("run_gate_summary"),
  preempt:(._preempt_before_request_v1//null),
  marker_forcefinal:(._postprocess_forcefinal_v1//null),
  degraded_n:(.degraded_tools|length)
}'
