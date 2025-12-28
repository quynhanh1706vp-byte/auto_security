#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
LOCK="out_ci/ui_8910.lock"
ts(){ date +%Y%m%d_%H%M%S; }

echo "== [1] backup + patch jsonify shim =="
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
cp -f "$APP" "$APP.bak_jsonifyshim_$(ts)"
echo "[BACKUP] $APP.bak_jsonifyshim_$(ts)"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_STATUS_V2_JSONIFY_SHIM_V1 ==="
if TAG in txt:
    print("[OK] jsonify shim already present, skip")
    raise SystemExit(0)

# must have postprocess; if missing, add minimal safe one
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
    # commercial: final + ci_dir => ok=true (don’t block UI)
    try:
        if resp.get("final") is True and ci_dir and resp.get("ok") is False:
            resp.setdefault("warnings", []).append({"reason":"final_run_status_partial","prev_error":resp.get("error"),"prev_http_code":resp.get("http_code")})
            resp["ok"] = True
            resp["http_code"] = 200
    except Exception:
        pass
    return resp
'''
    # insert helper after last import
    m = list(re.finditer(r'^\s*(from|import)\s+.*$', txt, flags=re.M))
    if m:
        at = m[-1].end()
        txt = txt[:at] + "\n\n" + helper + "\n" + txt[at:]
    else:
        txt = helper + "\n" + txt

# find def api_vsp_run_status_v2
m = re.search(r'^(\s*)def\s+api_vsp_run_status_v2\s*\(.*\)\s*:', txt, flags=re.M)
if not m:
    p.write_text(txt, encoding="utf-8")
    print("[WARN] cannot find def api_vsp_run_status_v2; wrote helper only")
    raise SystemExit(0)

def_indent = m.group(1)
body_indent = def_indent + (" " * 4)

shim = f"""
{body_indent}{TAG}
{body_indent}_jsonify_orig = jsonify
{body_indent}def jsonify(obj=None, *args, **kwargs):
{body_indent}    try:
{body_indent}        obj = _vsp_status_v2_postprocess(obj)
{body_indent}    except Exception:
{body_indent}        pass
{body_indent}    return _jsonify_orig(obj, *args, **kwargs)
"""

# insert shim right after def line
line_end = txt.find("\n", m.end())
if line_end == -1:
    line_end = len(txt)
txt = txt[:line_end+1] + shim + txt[line_end+1:]

p.write_text(txt, encoding="utf-8")
print("[OK] inserted jsonify shim into api_vsp_run_status_v2")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== [2] force free port 8910 + clear lock =="
ss -lptn 2>/dev/null | grep -E ':8910\b' || true
PIDS="$(ss -lptn 2>/dev/null | awk '/:8910[[:space:]]/ {print $NF}' | sed 's/.*pid=//;s/,.*//' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' || true)"
if [ -n "${PIDS// /}" ]; then
  echo "[KILL] pids: $PIDS"
  for pid in $PIDS; do kill -9 "$pid" 2>/dev/null || true; done
fi
rm -f "$LOCK" 2>/dev/null || true

echo "== [3] restart commercial =="
./bin/restart_8910_gunicorn_commercial_v5.sh || true

echo "== [4] verify injection =="
curl -sS http://127.0.0.1:8910/healthz || true
echo
RID="$(curl -sS "http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{
  ok,http_code,status,error:(.error//null),
  ci_run_dir, overall_verdict,
  has_semgrep:has("semgrep_summary"),
  has_trivy:has("trivy_summary"),
  has_run_gate:has("run_gate_summary"),
  warnings:(.warnings//null)
}'
