#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
LOCK="out_ci/ui_8910.lock"
ts(){ date +%Y%m%d_%H%M%S; }

echo "== [1] backup =="
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
cp -f "$APP" "$APP.bak_viewwrap_v3_$(ts)"
echo "[BACKUP] $APP.bak_viewwrap_v3_$(ts)"

echo "== [2] patch wrapper -> V3 (app.make_response) =="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# find start of wrapper V2 (or V1) and replace to EOF
start = None
for tag in [
    "# === VSP_RUN_STATUS_V2_VIEW_WRAPPER_V2 ===",
    "# === VSP_RUN_STATUS_V2_VIEW_WRAPPER_V1 ===",
]:
    i = txt.find(tag)
    if i != -1:
        start = i
        break

if start is None:
    print("[ERR] cannot find existing wrapper block to replace")
    raise SystemExit(2)

new_block = r'''
# === VSP_RUN_STATUS_V2_VIEW_WRAPPER_V3 ===
def _vsp_wrap_run_status_v2_endpoint(_app):
    import json
    # find endpoint by rule containing run_status_v2
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

        # normalize anything Flask can return -> Response
        try:
            resp_obj = _app.make_response(rv)
        except Exception:
            return rv

        # try parse JSON payload robustly
        data = None
        try:
            raw = resp_obj.get_data(as_text=True)
            raw = (raw or "").strip()
            if raw.startswith("{") and raw.endswith("}"):
                data = json.loads(raw)
        except Exception:
            data = None

        if isinstance(data, dict):
            # postprocess + inject summaries
            try:
                data2 = _vsp_status_v2_postprocess(data)
            except Exception:
                data2 = data

            # marker proves wrapper executed
            try:
                data2["_postprocess_v3"] = True
            except Exception:
                pass

            # IMPORTANT: if postprocess injected any gate/summary -> soften 500 to 200 for UI render
            try:
                ci_dir = data2.get("ci_run_dir") or data2.get("ci_dir") or data2.get("run_dir")
                has_any_gate = any(k in data2 for k in ("run_gate_summary","semgrep_summary","trivy_summary"))
                if ci_dir and has_any_gate and (data2.get("ok") is False or data2.get("http_code") == 500):
                    data2.setdefault("warnings", []).append({
                        "reason": "soften_http_500_when_gate_exists",
                        "prev_error": data2.get("error"),
                        "prev_http_code": data2.get("http_code"),
                    })
                    data2["ok"] = True
                    data2["http_code"] = 200
            except Exception:
                pass

            from flask import jsonify as _jsonify
            out = _jsonify(data2)

            # keep headers best-effort, but force JSON
            try:
                for hk, hv in resp_obj.headers.items():
                    if hk.lower() not in ("content-length", "content-type"):
                        out.headers[hk] = hv
            except Exception:
                pass

            # set status_code:
            # - prefer data2["http_code"] if present, else keep original
            try:
                out.status_code = int(data2.get("http_code") or resp_obj.status_code or 200)
            except Exception:
                out.status_code = resp_obj.status_code or 200

            return out

        # non-json body => return original response
        return resp_obj

    _app.view_functions[ep] = wrapped
    return True, ep

# run on import
try:
    _ok, _info = _vsp_wrap_run_status_v2_endpoint(app)
    print(f"[VSP_RUN_STATUS_V2_VIEW_WRAPPER_V3] ok={_ok} info={_info}")
except Exception as _e:
    print(f"[VSP_RUN_STATUS_V2_VIEW_WRAPPER_V3] failed: {_e}")
'''

txt2 = txt[:start] + new_block + "\n"
p.write_text(txt2, encoding="utf-8")
print("[OK] wrapper replaced with V3 (make_response)")
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
  postprocess:(._postprocess_v3//null),
  warnings:(.warnings//null)
}'
