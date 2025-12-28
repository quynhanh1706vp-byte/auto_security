#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_status_degraded_finish_${TS}"
echo "[BACKUP] $F.bak_status_degraded_finish_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# 1) Ensure helper block exists once
if "VSP_STATUS_DEGRADED_FINISH_V1" not in txt:
    helper = r'''
# === VSP_STATUS_DEGRADED_FINISH_V1 ===
def _vsp_read_json_file(path):
    try:
        import json
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return json.load(f)
    except Exception:
        return None

def _vsp_guess_final_and_reason(ci_run_dir, state_obj):
    """
    Commercial-ish finish logic:
    - final only when artifacts indicate end (SUMMARY.txt or findings_unified.json)
    - finish_reason hints for UI
    """
    import os, time
    ci = ci_run_dir or ""
    summary = os.path.join(ci, "SUMMARY.txt")
    findings = os.path.join(ci, "reports", "findings_unified.json")
    deg = os.path.join(ci, "degraded_tools.json")

    degraded = _vsp_read_json_file(deg) if (ci and os.path.isfile(deg)) else None

    completed = False
    if ci and (os.path.isfile(summary) or os.path.isfile(findings)):
        completed = True

    # stall detection from updated_at in uireq state
    stall_sec = int(os.environ.get("VSP_STATUS_STALL_SEC", "900"))  # 15m default
    updated_at = None
    try:
        updated_at = state_obj.get("updated_at")
    except Exception:
        updated_at = None

    stalled = False
    if (not completed) and updated_at:
        try:
            # updated_at may be iso string; fall back to mtime if parsing fails
            import datetime
            t = datetime.datetime.fromisoformat(str(updated_at).replace("Z",""))
            if (datetime.datetime.now() - t).total_seconds() > stall_sec:
                stalled = True
        except Exception:
            pass

    final = bool(completed)

    if completed:
        if isinstance(degraded, dict) and degraded:
            finish_reason = "completed_degraded"
        else:
            finish_reason = "completed"
    else:
        finish_reason = "running"
        if stalled:
            finish_reason = "stalled"

    return final, finish_reason, degraded
# === END VSP_STATUS_DEGRADED_FINISH_V1 ===
'''
    # Insert helper near top (after imports). Try after first blank line following imports.
    m = re.search(r'^(import .+\n)+\n', txt, flags=re.M)
    if m:
        ins = m.end()
        txt = txt[:ins] + helper + "\n" + txt[ins:]
    else:
        txt = helper + "\n" + txt

# 2) Patch run_status_v1 handler: add degraded_tools + finish_reason + tighten final
# We look for the route function by pattern '/api/vsp/run_status_v1' and patch return payload nearby.
route_idx = txt.find("/api/vsp/run_status_v1")
if route_idx == -1:
    raise SystemExit("[ERR] cannot find /api/vsp/run_status_v1 in vsp_demo_app.py")

# Find a "return jsonify(" after that route
m = re.search(r'return\s+jsonify\(\s*([a-zA-Z0-9_]+)\s*\)\s*', txt[route_idx:])  # return jsonify(resp)
if not m:
    # alternative: return jsonify({...})
    m2 = re.search(r'return\s+jsonify\(\s*\{', txt[route_idx:])
    if not m2:
        raise SystemExit("[ERR] cannot find return jsonify(...) in run_status_v1 handler")
    # We'll inject before 'return jsonify({'
    inject_point = route_idx + m2.start()
    patch = r'''
    # === VSP_STATUS_DEGRADED_FINISH_V1 PATCH (dict-inline) ===
    try:
        ci_run_dir = (resp.get("ci_run_dir") or resp.get("ci_dir") or "")
        final2, reason2, degraded2 = _vsp_guess_final_and_reason(ci_run_dir, state)
        resp["finish_reason"] = reason2
        resp["degraded_tools"] = degraded2
        # tighten final: only trust artifacts-based completion
        resp["final"] = bool(final2)
    except Exception as _e:
        resp["finish_reason"] = resp.get("finish_reason") or "running"
    # === END PATCH ===
'''
    txt = txt[:inject_point] + patch + txt[inject_point:]
else:
    resp_var = m.group(1)
    # Insert before that return
    inject_point = route_idx + m.start()
    patch = f'''
    # === VSP_STATUS_DEGRADED_FINISH_V1 PATCH (resp-var) ===
    try:
        ci_run_dir = ({resp_var}.get("ci_run_dir") or {resp_var}.get("ci_dir") or "")
        final2, reason2, degraded2 = _vsp_guess_final_and_reason(ci_run_dir, state)
        {resp_var}["finish_reason"] = reason2
        {resp_var}["degraded_tools"] = degraded2
        # tighten final: only trust artifacts-based completion
        {resp_var}["final"] = bool(final2)
    except Exception as _e:
        {resp_var}["finish_reason"] = {resp_var}.get("finish_reason") or "running"
    # === END PATCH ===
'''
    if "VSP_STATUS_DEGRADED_FINISH_V1 PATCH" not in txt[route_idx:route_idx+4000]:
        txt = txt[:inject_point] + patch + txt[inject_point:]

p.write_text(txt, encoding="utf-8")
print("[OK] patched run_status_v1 to include degraded_tools + finish_reason + tightened final")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
