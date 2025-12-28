#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
LOCK="out_ci/ui_8910.lock"
ts(){ date +%Y%m%d_%H%M%S; }

echo "== [1] backup =="
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
cp -f "$APP" "$APP.bak_wsgi_preempt_$(ts)"
echo "[BACKUP] $APP.bak_wsgi_preempt_$(ts)"

echo "== [2] install WSGI middleware preempt (replace if exists) =="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

BEGIN = "# === VSP_RUN_STATUS_V2_WSGI_PREEMPT_V1_BEGIN ==="
END   = "# === VSP_RUN_STATUS_V2_WSGI_PREEMPT_V1_END ==="

block = r'''
# === VSP_RUN_STATUS_V2_WSGI_PREEMPT_V1_BEGIN ===
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

def _vsp_build_final_status_from_artifacts_w1(rid: str):
    ci_dir, rid_norm = _vsp_pick_ci_dir_from_rid(rid)
    if not ci_dir:
        return {
            "ok": False, "http_code": 404, "status": "NOT_FOUND",
            "error": "CI_RUN_DIR_NOT_FOUND",
            "rid": rid, "rid_norm": rid_norm, "ci_run_dir": None,
            "final": True, "_wsgi_preempt_v1": True,
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
        "_wsgi_preempt_v1": True,
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

class _VSPStatusV2PreemptMiddleware:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            if path.startswith("/api/vsp/run_status_v2/"):
                rid = path.split("/api/vsp/run_status_v2/", 1)[-1].strip("/")
                data = _vsp_build_final_status_from_artifacts_w1(rid)

                import json
                body = json.dumps(data, ensure_ascii=False).encode("utf-8")
                code = int(data.get("http_code") or 200)
                status = f"{code} OK" if code < 400 else f"{code} ERROR"
                headers = [
                    ("Content-Type", "application/json; charset=utf-8"),
                    ("Content-Length", str(len(body))),
                    ("X-VSP-WSGI-PREEMPT", "1"),
                ]
                start_response(status, headers)
                return [body]
        except Exception:
            # if anything goes wrong, fall back to underlying app
            pass

        return self.app(environ, start_response)

# install middleware OUTERMOST
try:
    app.wsgi_app = _VSPStatusV2PreemptMiddleware(app.wsgi_app)
    print("[VSP_WSGI_PREEMPT_V1] installed")
except Exception as _e:
    print(f"[VSP_WSGI_PREEMPT_V1] failed: {_e}")
# === VSP_RUN_STATUS_V2_WSGI_PREEMPT_V1_END ===
'''

if BEGIN in txt and END in txt:
    txt = re.sub(re.escape(BEGIN)+r".*?"+re.escape(END), block.strip(), txt, flags=re.S)
else:
    txt = txt + "\n\n" + block + "\n"

p.write_text(txt, encoding="utf-8")
print("[OK] installed/updated WSGI preempt")
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

echo "== [4] verify (must NOT be null) =="
RID="RUN_VSP_CI_20251215_005247"
echo "RID=$RID"

echo "-- HEADERS --"
curl -sS -D - "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" -o /tmp/_rsp.json >/dev/null
grep -E "HTTP/|Content-Type|Content-Length|X-VSP-WSGI-PREEMPT" -n /tmp/_rsp.json || true

echo "-- RAW (first 120 chars) --"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | head -c 120
echo; echo

echo "-- JSON CHECK --"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{
  ok,http_code,status,error:(.error//null),
  ci_run_dir, overall_verdict,
  marker:(._wsgi_preempt_v1//null),
  has_kics:has("kics_summary"),
  has_semgrep:has("semgrep_summary"),
  has_trivy:has("trivy_summary"),
  has_run_gate:has("run_gate_summary"),
  degraded_n:(.degraded_tools|length)
}'
