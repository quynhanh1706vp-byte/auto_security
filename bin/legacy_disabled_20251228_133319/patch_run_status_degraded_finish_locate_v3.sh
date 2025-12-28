#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_locate_v3_${TS}"
echo "[BACKUP] $F.bak_locate_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# 1) Helper block (insert once)
if "VSP_STATUS_DEGRADED_FINISH_V3" not in txt:
    helper = r'''
# === VSP_STATUS_DEGRADED_FINISH_V3 ===
def _vsp_read_json_file(path):
    try:
        import json
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return json.load(f)
    except Exception:
        return None

def _vsp_guess_final_and_reason(ci_run_dir, state_obj):
    import os, datetime
    ci = (ci_run_dir or "").strip()
    summary = os.path.join(ci, "SUMMARY.txt")
    findings = os.path.join(ci, "reports", "findings_unified.json")
    deg = os.path.join(ci, "degraded_tools.json")

    degraded = _vsp_read_json_file(deg) if (ci and os.path.isfile(deg)) else None
    completed = bool(ci and (os.path.isfile(summary) or os.path.isfile(findings)))

    stall_sec = int(os.environ.get("VSP_STATUS_STALL_SEC", "900"))
    stalled = False
    updated_at = None
    try:
        updated_at = (state_obj or {}).get("updated_at")
    except Exception:
        updated_at = None

    if (not completed) and updated_at:
        try:
            t = datetime.datetime.fromisoformat(str(updated_at).replace("Z",""))
            stalled = (datetime.datetime.now() - t).total_seconds() > stall_sec
        except Exception:
            pass

    if completed:
        if isinstance(degraded, dict) and degraded:
            return True, "completed_degraded", degraded
        return True, "completed", degraded
    return False, ("stalled" if stalled else "running"), degraded
# === END VSP_STATUS_DEGRADED_FINISH_V3 ===
'''
    m = re.search(r'^(?:from\s+\S+\s+import\s+.*\n|import\s+.*\n)+\n', txt, flags=re.M)
    ins = m.end() if m else 0
    txt = txt[:ins] + helper + "\n" + txt[ins:]

# 2) Find location containing "run_status_v1"
needle = "run_status_v1"
pos = txt.find(needle)
if pos == -1:
    raise SystemExit("[ERR] cannot find 'run_status_v1' string in vsp_demo_app.py")

# 3) Find nearest following "def <name>(" after pos (within some window)
mdef = re.search(r'^[ \t]*def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(', txt[pos:], flags=re.M)
if not mdef:
    # fallback: find nearest preceding def (if route added via add_url_rule below def)
    mdef2 = None
    for m in re.finditer(r'^[ \t]*def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(', txt, flags=re.M):
        if m.start() < pos:
            mdef2 = m
        else:
            break
    if not mdef2:
        raise SystemExit("[ERR] cannot find any def() around run_status_v1")
    fn_start = mdef2.start()
else:
    fn_start = pos + mdef.start()

# 4) Determine function block end: next top-level decorator or def after fn_start
mend = re.search(r'\n(?=@|def\s+)', txt[fn_start+1:], flags=re.M)
fn_end = (fn_start + 1 + mend.start()) if mend else len(txt)
block = txt[fn_start:fn_end]

# already patched?
if "VSP_STATUS_DEGRADED_FINISH_V3_PATCH" in block:
    p.write_text(txt, encoding="utf-8")
    print("[OK] already patched V3")
    raise SystemExit(0)

# 5) Find "return jsonify(<var>)" inside that function
rj = re.search(r'^(?P<indent>[ \t]*)return\s+jsonify\(\s*(?P<rv>[a-zA-Z0-9_]+)\s*\)\s*$', block, flags=re.M)
if not rj:
    # show some context for debugging
    ctx = "\n".join(block.splitlines()[:60])
    raise SystemExit("[ERR] cannot find 'return jsonify(VAR)' inside handler. First 60 lines:\n" + ctx)

indent = rj.group("indent")
rv = rj.group("rv")

patch = f"""{indent}# === VSP_STATUS_DEGRADED_FINISH_V3_PATCH ===
{indent}try:
{indent}    _state = locals().get("state") or locals().get("st") or locals().get("uireq") or {{}}
{indent}    _resp = {rv}
{indent}    _ci = (_resp.get("ci_run_dir") or _resp.get("ci_dir") or _state.get("ci_run_dir") or _state.get("ci_dir") or "")
{indent}    _final2, _reason2, _degraded2 = _vsp_guess_final_and_reason(_ci, _state)
{indent}    _resp["finish_reason"] = _reason2
{indent}    _resp["degraded_tools"] = _degraded2
{indent}    _resp["final"] = bool(_final2)
{indent}except Exception:
{indent}    pass
{indent}# === END VSP_STATUS_DEGRADED_FINISH_V3_PATCH ===
"""

insert_at = fn_start + rj.start()
txt = txt[:insert_at] + patch + txt[insert_at:]

p.write_text(txt, encoding="utf-8")
print("[OK] patched run_status_v1 by locate-by-string V3")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
