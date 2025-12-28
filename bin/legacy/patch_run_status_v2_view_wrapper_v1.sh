#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
LOCK="out_ci/ui_8910.lock"
ts(){ date +%Y%m%d_%H%M%S; }

echo "== [1] backup + patch app (view wrapper) =="
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
cp -f "$APP" "$APP.bak_viewwrap_$(ts)"
echo "[BACKUP] $APP.bak_viewwrap_$(ts)"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_STATUS_V2_VIEW_WRAPPER_V1 ==="
if TAG in txt:
    print("[OK] view wrapper already present, skip")
    raise SystemExit(0)

# Ensure postprocess exists (minimal, safe)
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
    # commercial: if has ci_dir (artifacts exist), allow UI render
    try:
        if ci_dir and resp.get("ok") is False:
            # only flip when we actually have at least one gate file
            has_any = any(k in resp for k in ("run_gate_summary","semgrep_summary","trivy_summary"))
            if has_any:
                resp.setdefault("warnings", []).append({"reason":"status_v2_soft_error","prev_error":resp.get("error"),"prev_http_code":resp.get("http_code")})
                resp["ok"] = True
                resp["http_code"] = 200
    except Exception:
        pass
    return resp
'''
    # insert after last import
    m = list(re.finditer(r'^\s*(from|import)\s+.*$', txt, flags=re.M))
    if m:
        at = m[-1].end()
        txt = txt[:at] + "\n\n" + helper + "\n" + txt[at:]
    else:
        txt = helper + "\n" + txt

wrapper = r'''
# === VSP_RUN_STATUS_V2_VIEW_WRAPPER_V1 ===
try:
    from flask import Response as _FlaskResponse
except Exception:
    _FlaskResponse = None

def _vsp_wrap_run_status_v2_endpoint(_app):
    ep = None
    try:
        for r in _app.url_map.iter_rules():
            if "run_status_v2" in str(r.rule):
                ep = r.endpoint
                break
    except Exception:
        ep = None
    if not ep:
        return False, "endpoint_not_found"
    if ep not in _app.view_functions:
        return False, f"endpoint_missing_in_view_functions:{ep}"
    orig = _app.view_functions[ep]

    def wrapped(*a, **k):
        rv = orig(*a, **k)

        # normalize flask return types
        body, status, headers = rv, None, None
        if isinstance(rv, tuple):
            if len(rv) == 2:
                body, status = rv
            elif len(rv) == 3:
                body, status, headers = rv

        # case 1: dict body
        if isinstance(body, dict):
            body2 = _vsp_status_v2_postprocess(body)
            if status is None and headers is None:
                return body2
            if headers is None:
                return (body2, status)
            return (body2, status, headers)

        # case 2: Response body
        try:
            if _FlaskResponse is not None and isinstance(body, _FlaskResponse):
                data = None
                try:
                    data = body.get_json(silent=True)
                except Exception:
                    data = None
                if isinstance(data, dict):
                    data2 = _vsp_status_v2_postprocess(data)
                    # rebuild JSON response, keep status code
                    from flask import jsonify as _jsonify
                    resp2 = _jsonify(data2)
                    resp2.status_code = body.status_code
                    # keep headers (best-effort)
                    try:
                        for hk, hv in body.headers.items():
                            if hk.lower() not in ("content-length",):
                                resp2.headers[hk] = hv
                    except Exception:
                        pass
                    if status is None and headers is None:
                        return resp2
                    if headers is None:
                        return (resp2, status)
                    return (resp2, status, headers)
        except Exception:
            pass

        return rv

    _app.view_functions[ep] = wrapped
    return True, ep

# run on import
try:
    _ok, _info = _vsp_wrap_run_status_v2_endpoint(app)
    print(f"[VSP_RUN_STATUS_V2_VIEW_WRAPPER_V1] ok={_ok} info={_info}")
except Exception as _e:
    print(f"[VSP_RUN_STATUS_V2_VIEW_WRAPPER_V1] failed: {_e}")
'''

txt = txt + "\n\n" + wrapper + "\n"
p.write_text(txt, encoding="utf-8")
print("[OK] appended view wrapper")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== [2] restart clean 8910 =="
# kill any listener
PIDS="$(ss -lptn 2>/dev/null | awk '/:8910[[:space:]]/ {print $NF}' | sed 's/.*pid=//;s/,.*//' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' || true)"
if [ -n "${PIDS// /}" ]; then
  echo "[KILL] pids: $PIDS"
  for pid in $PIDS; do kill -9 "$pid" 2>/dev/null || true; done
fi
rm -f "$LOCK" 2>/dev/null || true

./bin/restart_8910_gunicorn_commercial_v5.sh || true

echo "== [3] verify =="
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
  warnings:(.warnings//null)
}'
