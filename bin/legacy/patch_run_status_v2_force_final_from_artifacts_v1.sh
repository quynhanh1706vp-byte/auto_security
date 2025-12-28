#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
LOCK="out_ci/ui_8910.lock"
ts(){ date +%Y%m%d_%H%M%S; }

echo "== [1] backup =="
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
cp -f "$APP" "$APP.bak_forcefinal_$(ts)"
echo "[BACKUP] $APP.bak_forcefinal_$(ts)"

echo "== [2] append FORCE_FINAL override =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_STATUS_V2_FORCE_FINAL_FROM_ARTIFACTS_V1 ==="
if TAG in txt:
    print("[OK] already installed, skip")
    raise SystemExit(0)

block = r'''
# === VSP_RUN_STATUS_V2_FORCE_FINAL_FROM_ARTIFACTS_V1 ===
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
    # normalize RUN_VSP_CI_YYYYmmdd_HHMMSS -> VSP_CI_YYYYmmdd_HHMMSS
    rid_norm = rid
    if rid_norm.startswith("RUN_VSP_CI_"):
        rid_norm = rid_norm.replace("RUN_VSP_CI_", "VSP_CI_", 1)
    if rid_norm.startswith("RUN_"):
        # common pattern
        rid_norm = rid_norm.replace("RUN_", "", 1)
    # if already VSP_CI_*
    base = Path("/home/test/Data/SECURITY-10-10-v4/out_ci")
    cand = base / rid_norm
    if cand.exists() and cand.is_dir():
        return str(cand), rid_norm
    # fallback: try direct rid
    cand2 = base / rid
    if cand2.exists() and cand2.is_dir():
        return str(cand2), rid
    return None, rid_norm

def _vsp_build_final_status_from_artifacts(rid: str):
    ci_dir, rid_norm = _vsp_pick_ci_dir_from_rid(rid)
    if not ci_dir:
        return {
            "ok": False,
            "http_code": 404,
            "status": "NOT_FOUND",
            "error": "CI_RUN_DIR_NOT_FOUND",
            "rid": rid,
            "rid_norm": rid_norm,
            "ci_run_dir": None,
            "final": True,
        }

    # load summaries
    kics = _vsp_json_load(f"{ci_dir}/kics_summary.json") or _vsp_json_load(f"{ci_dir}/kics/kics_summary.json")
    semg = _vsp_json_load(f"{ci_dir}/semgrep_summary.json") or _vsp_json_load(f"{ci_dir}/semgrep/semgrep_summary.json")
    triv = _vsp_json_load(f"{ci_dir}/trivy_summary.json") or _vsp_json_load(f"{ci_dir}/trivy/trivy_summary.json")
    gate = _vsp_json_load(f"{ci_dir}/run_gate_summary.json")

    degraded = _vsp_json_load(f"{ci_dir}/degraded_tools.json") or []
    if isinstance(degraded, dict):
        degraded = degraded.get("degraded_tools") or degraded.get("items") or []

    resp = {
        "ok": True,
        "http_code": 200,
        "status": "FINAL",
        "error": None,
        "rid": rid,
        "rid_norm": rid_norm,
        "ci_run_dir": ci_dir,
        "final": True,
        "progress_pct": 100,
        "stage_index": 0,
        "stage_total": 0,
        "stage_name": "FINAL",
        "stage_sig": "FINAL",
        "degraded_tools": degraded if isinstance(degraded, list) else [],
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

    # marker
    resp["_postprocess_forcefinal_v1"] = True
    return resp

def _vsp_force_override_run_status_v2(_app):
    ep = None
    try:
        for r in _app.url_map.iter_rules():
            if "run_status_v2" in str(r.rule):
                ep = r.endpoint
                break
    except Exception:
        ep = None
    if not ep or ep not in _app.view_functions:
        return False, f"endpoint_not_found:{ep}"

    def fixed(req_id):
        # IMPORTANT: return dict, Flask will jsonify it
        return _vsp_build_final_status_from_artifacts(req_id)

    _app.view_functions[ep] = fixed
    return True, ep

try:
    _ok, _info = _vsp_force_override_run_status_v2(app)
    print(f"[VSP_RUN_STATUS_V2_FORCE_FINAL_FROM_ARTIFACTS_V1] ok={_ok} info={_info}")
except Exception as _e:
    print(f"[VSP_RUN_STATUS_V2_FORCE_FINAL_FROM_ARTIFACTS_V1] failed: {_e}")
'''

txt2 = txt + "\n\n" + block + "\n"
p.write_text(txt2, encoding="utf-8")
print("[OK] appended FORCE_FINAL override")
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

echo "== [4] verify =="
curl -sS http://127.0.0.1:8910/healthz || true
echo
RID="$(curl -sS "http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{
  ok,http_code,status,error:(.error//null),
  ci_run_dir,
  overall_verdict,
  has_kics:has("kics_summary"),
  has_semgrep:has("semgrep_summary"),
  has_trivy:has("trivy_summary"),
  has_run_gate:has("run_gate_summary"),
  marker:(._postprocess_forcefinal_v1//null),
  degraded_n:(.degraded_tools|length)
}'
