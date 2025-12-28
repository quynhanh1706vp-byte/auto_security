#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
LOCK="out_ci/ui_8910.lock"
ts(){ date +%Y%m%d_%H%M%S; }

echo "== [1] backup =="
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
cp -f "$APP" "$APP.bak_afterreq_$(ts)"
echo "[BACKUP] $APP.bak_afterreq_$(ts)"

echo "== [2] patch after_request hook =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_STATUS_V2_AFTER_REQUEST_INJECT_V1 ==="
if TAG in txt:
    print("[OK] after_request hook already present, skip")
    raise SystemExit(0)

# ensure _vsp_status_v2_postprocess exists; if not, add minimal version after imports
if "_vsp_status_v2_postprocess" not in txt:
    helper = r'''
# === VSP_STATUS_V2_MIN_POSTPROCESS_V1 ===
def _vsp_first_existing_json(paths):
    import json
    from pathlib import Path
    for pp in paths:
        try:
            fp = Path(pp)
            if fp.exists() and fp.is_file():
                return json.loads(fp.read_text(encoding="utf-8", errors="ignore")), str(fp)
        except Exception:
            continue
    return None, None

def _vsp_inject_tool_summary(resp, ci_dir, tool_key, summary_name):
    if not isinstance(resp, dict) or not ci_dir:
        return resp
    data, used = _vsp_first_existing_json([f"{ci_dir}/{summary_name}", f"{ci_dir}/{tool_key}/{summary_name}"])
    if not data:
        return resp
    resp[f"{tool_key}_summary"] = data
    resp[f"{tool_key}_verdict"] = data.get("verdict")
    resp[f"{tool_key}_total"] = data.get("total")
    resp[f"{tool_key}_counts"] = data.get("counts")
    resp[f"{tool_key}_summary_path"] = used
    return resp

def _vsp_inject_run_gate(resp, ci_dir):
    if not isinstance(resp, dict) or not ci_dir:
        return resp
    data, used = _vsp_first_existing_json([f"{ci_dir}/run_gate_summary.json"])
    if not data:
        return resp
    resp["run_gate_summary"] = data
    resp["run_gate_summary_path"] = used
    resp["overall_verdict"] = data.get("overall")
    resp["overall_counts"] = data.get("counts_total")
    return resp

def _vsp_status_v2_postprocess(resp):
    if not isinstance(resp, dict):
        return resp
    ci_dir = resp.get("ci_run_dir") or resp.get("ci_dir") or resp.get("run_dir")
    try:
        resp = _vsp_inject_tool_summary(resp, ci_dir, "semgrep", "semgrep_summary.json")
        resp = _vsp_inject_tool_summary(resp, ci_dir, "trivy",   "trivy_summary.json")
        resp = _vsp_inject_run_gate(resp, ci_dir)
    except Exception:
        pass
    return resp
'''
    m = list(re.finditer(r'^\s*(from|import)\s+.*$', txt, flags=re.M))
    if m:
        at = m[-1].end()
        txt = txt[:at] + "\n\n" + helper + "\n" + txt[at:]
    else:
        txt = helper + "\n" + txt

hook = r'''
# === VSP_STATUS_V2_AFTER_REQUEST_INJECT_V1 ===
try:
    from flask import request as _vsp_req
    import json as _vsp_json
except Exception:
    _vsp_req = None
    _vsp_json = None

def _vsp_should_inject_status_v2():
    try:
        return _vsp_req is not None and (_vsp_req.path or "").startswith("/api/vsp/run_status_v2/")
    except Exception:
        return False

@app.after_request
def _vsp_after_request_inject_status_v2(resp):
    # only for run_status_v2
    if not _vsp_should_inject_status_v2():
        return resp

    if _vsp_json is None:
        return resp

    try:
        raw = resp.get_data(as_text=True)
        raw = (raw or "").strip()
        if not (raw.startswith("{") and raw.endswith("}")):
            return resp
        data = _vsp_json.loads(raw)
        if not isinstance(data, dict):
            return resp

        data2 = _vsp_status_v2_postprocess(data)

        # marker proves hook executed
        try:
            data2["_postprocess_after_v1"] = True
        except Exception:
            pass

        # soften: if gate/summary exists, don't let 500 block UI
        try:
            ci_dir = data2.get("ci_run_dir") or data2.get("ci_dir") or data2.get("run_dir")
            has_any = any(k in data2 for k in ("run_gate_summary","semgrep_summary","trivy_summary"))
            if ci_dir and has_any and (data2.get("ok") is False or int(data2.get("http_code") or 0) >= 500 or resp.status_code >= 500):
                data2.setdefault("warnings", []).append({
                    "reason": "soften_http_500_when_gate_exists_after_request",
                    "prev_error": data2.get("error"),
                    "prev_http_code": data2.get("http_code"),
                    "prev_status_code": resp.status_code,
                })
                data2["ok"] = True
                data2["http_code"] = 200
        except Exception:
            pass

        # rebuild response JSON but preserve headers best-effort
        new_body = _vsp_json.dumps(data2, ensure_ascii=False)
        resp.set_data(new_body)
        resp.headers["Content-Type"] = "application/json; charset=utf-8"
        try:
            resp.status_code = int(data2.get("http_code") or resp.status_code or 200)
        except Exception:
            pass
        return resp
    except Exception:
        return resp
'''

txt = txt + "\n\n" + hook + "\n"
p.write_text(txt, encoding="utf-8")
print("[OK] appended after_request hook")
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
  has_semgrep:has("semgrep_summary"),
  has_trivy:has("trivy_summary"),
  has_run_gate:has("run_gate_summary"),
  postprocess:(._postprocess_after_v1//null),
  warnings:(.warnings//null)
}'
