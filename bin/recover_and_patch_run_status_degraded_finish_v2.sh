#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "[STEP] 1) Find a compilable vsp_demo_app.py (current or backups)..."

# candidates: current + all backups (newest first)
mapfile -t CANDS < <(ls -1t "$F" "$F".bak_* 2>/dev/null || true)

GOOD=""
for c in "${CANDS[@]}"; do
  if python3 -m py_compile "$c" >/dev/null 2>&1; then
    GOOD="$c"
    break
  fi
done

if [ -z "$GOOD" ]; then
  echo "[ERR] No compilable candidate found among current+backups."
  echo "Try: ls -1t vsp_demo_app.py.bak_* | head"
  exit 2
fi

if [ "$GOOD" != "$F" ]; then
  cp -f "$GOOD" "$F"
  echo "[RECOVER] Restored $F from $GOOD"
else
  echo "[OK] Current $F already compilable."
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_before_patch_v2_${TS}"
echo "[BACKUP] $F.bak_before_patch_v2_${TS}"

echo "[STEP] 2) Apply safe patch (degraded_tools + finish_reason + tightened final)..."

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# ---- helper block (insert once) ----
if "VSP_STATUS_DEGRADED_FINISH_V2" not in txt:
    helper = r'''
# === VSP_STATUS_DEGRADED_FINISH_V2 ===
def _vsp_read_json_file(path):
    try:
        import json
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return json.load(f)
    except Exception:
        return None

def _vsp_guess_final_and_reason(ci_run_dir, state_obj):
    """
    final only when artifacts indicate end:
      - SUMMARY.txt OR reports/findings_unified.json exists
    finish_reason:
      - completed | completed_degraded | running | stalled
    """
    import os, datetime

    ci = (ci_run_dir or "").strip()
    summary = os.path.join(ci, "SUMMARY.txt")
    findings = os.path.join(ci, "reports", "findings_unified.json")
    deg = os.path.join(ci, "degraded_tools.json")

    degraded = _vsp_read_json_file(deg) if (ci and os.path.isfile(deg)) else None
    completed = bool(ci and (os.path.isfile(summary) or os.path.isfile(findings)))

    stall_sec = int(os.environ.get("VSP_STATUS_STALL_SEC", "900"))  # 15m
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

    final = completed

    if completed:
        if isinstance(degraded, dict) and degraded:
            finish_reason = "completed_degraded"
        else:
            finish_reason = "completed"
    else:
        finish_reason = "stalled" if stalled else "running"

    return bool(final), str(finish_reason), degraded
# === END VSP_STATUS_DEGRADED_FINISH_V2 ===
'''
    # insert after imports block (best-effort)
    m = re.search(r'^(?:from\s+\S+\s+import\s+.*\n|import\s+.*\n)+\n', txt, flags=re.M)
    ins = m.end() if m else 0
    txt = txt[:ins] + helper + "\n" + txt[ins:]

# ---- locate run_status_v1 handler and patch inside it safely ----
if "VSP_STATUS_DEGRADED_FINISH_V2_PATCH" not in txt:
    # find decorator for run_status_v1
    m = re.search(r'@app\.route\([^\n]*run_status_v1[^\n]*\)\s*\n\s*def\s+([a-zA-Z0-9_]+)\s*\(', txt)
    if not m:
        raise SystemExit("[ERR] Cannot find @app.route(...run_status_v1...) def handler")

    fn_name = m.group(1)

    # find function block start
    fn_start = m.start()
    # naive function end: next "\ndef " at column 0 (or start-of-line) after this function
    m2 = re.search(r'\n(?=def\s+|@app\.route)', txt[m.end():])
    fn_end = (m.end() + m2.start()) if m2 else len(txt)

    block = txt[fn_start:fn_end]

    # find "return jsonify(...)" inside block
    rj = re.search(r'^(?P<indent>[ \t]*)return\s+jsonify\(\s*(?P<rv>[a-zA-Z0-9_]+)\s*\)\s*$', block, flags=re.M)
    if not rj:
        # alternative: return jsonify({...})
        rj2 = re.search(r'^(?P<indent>[ \t]*)return\s+jsonify\(\s*\{', block, flags=re.M)
        if not rj2:
            raise SystemExit("[ERR] Cannot find return jsonify(...) inside run_status_v1 handler")
        indent = rj2.group("indent")
        # for inline dict, we will not try to reference resp var; just skip wiring
        raise SystemExit("[ERR] run_status_v1 returns inline dict; need resp var style. (Tell me, but we can also auto-refactor.)")
    else:
        indent = rj.group("indent")
        resp_var = rj.group("rv")

    patch = f"""{indent}# === VSP_STATUS_DEGRADED_FINISH_V2_PATCH ===
{indent}try:
{indent}    _state = locals().get("state") or locals().get("st") or locals().get("uireq") or {{}}
{indent}    _resp = {resp_var}
{indent}    _ci = (_resp.get("ci_run_dir") or _resp.get("ci_dir") or _state.get("ci_run_dir") or _state.get("ci_dir") or "")
{indent}    _final2, _reason2, _degraded2 = _vsp_guess_final_and_reason(_ci, _state)
{indent}    _resp["finish_reason"] = _reason2
{indent}    _resp["degraded_tools"] = _degraded2
{indent}    _resp["final"] = bool(_final2)
{indent}except Exception:
{indent}    pass
{indent}# === END VSP_STATUS_DEGRADED_FINISH_V2_PATCH ===
"""

    # insert patch right BEFORE the return jsonify(resp_var) line
    insert_at = fn_start + (rj.start() if rj else 0)
    txt = txt[:insert_at] + patch + txt[insert_at:]

p.write_text(txt, encoding="utf-8")
print("[OK] Patched:", p)
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
