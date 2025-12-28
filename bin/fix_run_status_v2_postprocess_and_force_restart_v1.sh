#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
LOCK="out_ci/ui_8910.lock"

ts(){ date +%Y%m%d_%H%M%S; }

echo "== [1] backup + patch vsp_demo_app.py =="
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
cp -f "$APP" "$APP.bak_postprocess_v1_$(ts)"
echo "[BACKUP] $APP.bak_postprocess_v1_$(ts)"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

TAG = "# === VSP_RUN_STATUS_V2_POSTPROCESS_V1 ==="
if any(TAG in l for l in lines):
    print("[OK] postprocess already installed, skip patching")
    raise SystemExit(0)

text = "".join(lines)

# 1) Add postprocess helper after imports
helper = r'''
# === VSP_RUN_STATUS_V2_POSTPROCESS_V1 ===
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
    data, used = _vsp_first_existing_json([
        f"{ci_dir}/{summary_name}",
        f"{ci_dir}/{tool_key}/{summary_name}",
    ])
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
    """
    Commercial rule:
    - Always inject summaries if ci_run_dir exists.
    - If final==true and ci_run_dir exists: do NOT report ok=false/500 just because live progress/pid missing.
      Convert to ok=true with warnings so UI can render.
    """
    if not isinstance(resp, dict):
        return resp

    ci_dir = resp.get("ci_run_dir") or resp.get("ci_dir") or resp.get("run_dir")
    # inject P1 summaries
    try:
        resp = _vsp_inject_tool_summary(resp, ci_dir, "semgrep", "semgrep_summary.json")
        resp = _vsp_inject_tool_summary(resp, ci_dir, "trivy",   "trivy_summary.json")
        resp = _vsp_inject_run_gate(resp, ci_dir)
    except Exception:
        pass

    # normalize ok for final runs with artifacts
    try:
        if resp.get("final") is True and ci_dir:
            if resp.get("ok") is False:
                resp.setdefault("warnings", []).append({
                    "reason": "final_run_status_partial",
                    "prev_error": resp.get("error"),
                    "prev_http_code": resp.get("http_code"),
                })
                resp["ok"] = True
                resp["http_code"] = 200
                # keep status as ERROR if you want, but UI should use ok/overall_verdict
                resp["status"] = resp.get("status") or "FINAL"
    except Exception:
        pass

    return resp
'''

# insert helper after last import line
import_matches = list(re.finditer(r'^\s*(from|import)\s+.*$', text, flags=re.M))
if import_matches:
    at = import_matches[-1].end()
    text = text[:at] + "\n\n" + helper + "\n" + text[at:]
else:
    text = helper + "\n" + text

# 2) Patch run_status_v2 handler: rewrite every "return jsonify(X)" inside handler to postprocess
m = re.search(r'^\s*def\s+api_vsp_run_status_v2\s*\(.*\)\s*:', text, flags=re.M)
if not m:
    # fallback: still write helper; can't rewrite returns safely
    p.write_text(text, encoding="utf-8")
    print("[WARN] cannot find def api_vsp_run_status_v2; helper inserted only")
    raise SystemExit(0)

# find handler block by indentation
start = m.start()
# find end: next top-level def (no leading spaces) after start
m_end = re.search(r'^\s*def\s+\w+\s*\(', text[m.end():], flags=re.M)
end = len(text) if not m_end else (m.end() + m_end.start())

block = text[start:end]
rest  = text[end:]

# replace return jsonify(...)
def repl_return(line: str):
    # match: return jsonify(<expr>)
    mm = re.match(r'^(\s*)return\s+jsonify\((.*)\)\s*$', line)
    if not mm:
        return None
    indent, expr = mm.group(1), mm.group(2)
    return [
        f"{indent}__rsp = {expr}\n",
        f"{indent}__rsp = _vsp_status_v2_postprocess(__rsp)\n",
        f"{indent}return jsonify(__rsp)\n",
    ]

new_block_lines = []
changed = 0
for ln in block.splitlines(True):
    r = repl_return(ln)
    if r is not None:
        new_block_lines.extend(r)
        changed += 1
    else:
        new_block_lines.append(ln)

if changed == 0:
    # maybe uses flask.jsonify
    def repl_return2(line: str):
        mm = re.match(r'^(\s*)return\s+flask\.jsonify\((.*)\)\s*$', line)
        if not mm:
            return None
        indent, expr = mm.group(1), mm.group(2)
        return [
            f"{indent}__rsp = {expr}\n",
            f"{indent}__rsp = _vsp_status_v2_postprocess(__rsp)\n",
            f"{indent}return flask.jsonify(__rsp)\n",
        ]
    new_block_lines = []
    for ln in block.splitlines(True):
        r = repl_return2(ln)
        if r is not None:
            new_block_lines.extend(r)
            changed += 1
        else:
            new_block_lines.append(ln)

text2 = text[:start] + "".join(new_block_lines) + rest
p.write_text(text2, encoding="utf-8")
print(f"[OK] patched run_status_v2 returns: changed={changed}")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== [2] force free port 8910 (kill listeners) =="
# show listeners
ss -lptn 2>/dev/null | grep -E ':8910\b' || true

# kill any gunicorn/python holding 8910
PIDS="$(ss -lptn 2>/dev/null | awk '/:8910[[:space:]]/ {print $NF}' | sed 's/.*pid=//;s/,.*//' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' || true)"
if [ -n "${PIDS// /}" ]; then
  echo "[KILL] pids: $PIDS"
  for pid in $PIDS; do
    kill -9 "$pid" 2>/dev/null || true
  done
fi

# remove stale lock
rm -f "$LOCK" 2>/dev/null || true

echo "== [3] restart commercial =="
./bin/restart_8910_gunicorn_commercial_v5.sh || true

echo "== [4] verify =="
curl -sS http://127.0.0.1:8910/healthz || true
echo
RID="$(curl -sS "http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{ok,http_code,status,error:(.error//null), ci_run_dir, overall_verdict, has_semgrep:has("semgrep_summary"), has_trivy:has("trivy_summary"), has_run_gate:has("run_gate_summary"), warnings:(.warnings//null)}'
