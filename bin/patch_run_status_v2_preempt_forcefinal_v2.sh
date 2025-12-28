#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
LOCK="out_ci/ui_8910.lock"
ts(){ date +%Y%m%d_%H%M%S; }

echo "== [1] backup =="
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
cp -f "$APP" "$APP.bak_preempt_forcefinal_v2_$(ts)"
echo "[BACKUP] $APP.bak_preempt_forcefinal_v2_$(ts)"

echo "== [2] install PREEMPT_FORCEFINAL_V2 (replace if exists) =="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG_BEGIN = "# === VSP_RUN_STATUS_V2_PREEMPT_FORCEFINAL_V2_BEGIN ==="
TAG_END   = "# === VSP_RUN_STATUS_V2_PREEMPT_FORCEFINAL_V2_END ==="

block = r'''
# === VSP_RUN_STATUS_V2_PREEMPT_FORCEFINAL_V2_BEGIN ===
def _vsp_json_load(path):
    import json
    from pathlib import Path
    try:
        fp = Path(path)
        if fp.exists() and fp.is_file():
            return json.loads(fp.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        pass
    return None

def _vsp_pick_ci_dir_from_rid(rid: str):
    from pathlib import Path
    rid = (rid or "").strip()
    rid_norm = rid
    if rid_norm.startswith("RUN_VSP_CI_"):
        rid_norm = rid_norm.replace("RUN_VSP_CI_", "VSP_CI_", 1)
    if rid_norm.startswith("RUN_"):
        rid_norm = rid_norm.replace("RUN_", "", 1)
    base = Path("/home/test/Data/SECURITY-10-10-v4/out_ci")
    cand = base / rid_norm
    if cand.exists() and cand.is_dir():
        return str(cand), rid_norm
    cand2 = base / rid
    if cand2.exists() and cand2.is_dir():
        return str(cand2), rid
    return None, rid_norm

def _vsp_build_final_status_from_artifacts_v2(rid: str):
    ci_dir, rid_norm = _vsp_pick_ci_dir_from_rid(rid)
    if not ci_dir:
        return {
            "ok": False, "http_code": 404, "status": "NOT_FOUND",
            "error": "CI_RUN_DIR_NOT_FOUND",
            "rid": rid, "rid_norm": rid_norm, "ci_run_dir": None,
            "final": True, "_preempt_forcefinal_v2": True,
        }

    kics = _vsp_json_load(f"{ci_dir}/kics_summary.json") or _vsp_json_load(f"{ci_dir}/kics/kics_summary.json")
    semg = _vsp_json_load(f"{ci_dir}/semgrep_summary.json") or _vsp_json_load(f"{ci_dir}/semgrep/semgrep_summary.json")
    triv = _vsp_json_load(f"{ci_dir}/trivy_summary.json") or _vsp_json_load(f"{ci_dir}/trivy/trivy_summary.json")
    gate = _vsp_json_load(f"{ci_dir}/run_gate_summary.json")
    degraded = _vsp_json_load(f"{ci_dir}/degraded_tools.json") or []
    if isinstance(degraded, dict):
        degraded = degraded.get("degraded_tools") or degraded.get("items") or []

    resp = {
        "ok": True, "http_code": 200, "status": "FINAL", "error": None,
        "rid": rid, "rid_norm": rid_norm, "ci_run_dir": ci_dir,
        "final": True,
        "progress_pct": 100, "stage_name": "FINAL", "stage_sig": "FINAL",
        "stage_index": 0, "stage_total": 0,
        "degraded_tools": degraded if isinstance(degraded, list) else [],
        "_preempt_forcefinal_v2": True,
    }

    def inject(tool_key, data):
        if not isinstance(data, dict):
            return
        resp[f"{tool_key}_summary"] = data
        resp[f"{tool_key}_verdict"] = data.get("verdict")
        resp[f"{tool_key}_total"] = data.get("total")
        resp[f"{tool_key}_counts"] = data.get("counts")

    inject("kics", kics)
    inject("semgrep", semg)
    inject("trivy", triv)

    if isinstance(gate, dict):
        resp["run_gate_summary"] = gate
        resp["overall_verdict"] = gate.get("overall")
        resp["overall_counts"] = gate.get("counts_total")

    return resp

try:
    from flask import request as _vsp_req, jsonify as _vsp_jsonify
except Exception:
    _vsp_req = None
    _vsp_jsonify = None

@app.before_request
def _vsp_preempt_run_status_v2_forcefinal_v2():
    # HARD preempt: if path matches, we return FINAL object (never null)
    if _vsp_req is None or _vsp_jsonify is None:
        return None
    try:
        path = (_vsp_req.path or "")
        if not path.startswith("/api/vsp/run_status_v2/"):
            return None
        rid = path.split("/api/vsp/run_status_v2/", 1)[-1].strip("/")
        data = _vsp_build_final_status_from_artifacts_v2(rid)

        # log to gunicorn stdout -> out_ci/ui_8910.log
        try:
            print(f"[PREEMPT_FORCEFINAL_V2] path={path} rid={rid} ok={data.get('ok')} http={data.get('http_code')} ci={data.get('ci_run_dir')}")
        except Exception:
            pass

        resp = _vsp_jsonify(data)
        try:
            resp.status_code = int(data.get("http_code") or 200)
        except Exception:
            resp.status_code = 200
        return resp
    except Exception as e:
        try:
            print(f"[PREEMPT_FORCEFINAL_V2] exception: {e}")
        except Exception:
            pass
        return None
# === VSP_RUN_STATUS_V2_PREEMPT_FORCEFINAL_V2_END ===
'''

# Replace existing block if present
if TAG_BEGIN in txt and TAG_END in txt:
    txt = re.sub(
        re.escape(TAG_BEGIN) + r".*?" + re.escape(TAG_END),
        block.strip(),
        txt,
        flags=re.S
    )
else:
    txt = txt + "\n\n" + block + "\n"

p.write_text(txt, encoding="utf-8")
print("[OK] installed PREEMPT_FORCEFINAL_V2")
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

echo "== [4] verify RAW + marker =="
RID="$(curl -sS "http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"

echo "-- RAW (first 200 chars) --"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | head -c 200
echo; echo

echo "-- JSON CHECK --"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{
  ok,http_code,status,error:(.error//null),
  ci_run_dir, overall_verdict,
  marker:(._preempt_forcefinal_v2//null),
  has_kics:has("kics_summary"),
  has_semgrep:has("semgrep_summary"),
  has_trivy:has("trivy_summary"),
  has_run_gate:has("run_gate_summary"),
  degraded_n:(.degraded_tools|length)
}'

echo "== [5] confirm preempt log hit =="
tail -n 30 out_ci/ui_8910.log | sed 's/\r/\n/g' | grep -E "PREEMPT_FORCEFINAL_V2" || true
