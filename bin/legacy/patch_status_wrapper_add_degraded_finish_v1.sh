#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_wrapper_degraded_finish_${TS}"
echo "[BACKUP] $F.bak_wrapper_degraded_finish_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# ---- helper block (insert once) ----
if "VSP_STATUS_DEGRADED_FINISH_HELPER_V1" not in txt:
    helper = r'''
# === VSP_STATUS_DEGRADED_FINISH_HELPER_V1 ===
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
# === END VSP_STATUS_DEGRADED_FINISH_HELPER_V1 ===
'''
    m = re.search(r'^(?:from\s+\S+\s+import\s+.*\n|import\s+.*\n)+\n', txt, flags=re.M)
    ins = m.end() if m else 0
    txt = txt[:ins] + helper + "\n" + txt[ins:]

# ---- locate wrapper ----
wpos = txt.find("def _wrapped_status_contract_v2")
if wpos == -1:
    raise SystemExit("[ERR] cannot find def _wrapped_status_contract_v2 in file")

# limit search within wrapper function block
mend = re.search(r'\n(?=@|def\s+)', txt[wpos+1:], flags=re.M)
wend = (wpos + 1 + mend.start()) if mend else len(txt)
block = txt[wpos:wend]

if "VSP_STATUS_DEGRADED_FINISH_WRAPPER_PATCH_V1" in block:
    p.write_text(txt, encoding="utf-8")
    print("[OK] wrapper already patched")
    raise SystemExit(0)

# find line: if isinstance(data, dict):
mif = re.search(r'^(?P<indent>[ \t]*)if\s+isinstance\s*\(\s*data\s*,\s*dict\s*\)\s*:\s*$', block, flags=re.M)
if not mif:
    # show early block for debugging
    ctx = "\n".join(block.splitlines()[:80])
    raise SystemExit("[ERR] cannot find 'if isinstance(data, dict):' in wrapper. Head:\n" + ctx)

indent = mif.group("indent")  # indent of if-line
indent2 = indent + ("  " if "\t" not in indent else "\t")  # inside if-block

patch = f"""{indent2}# === VSP_STATUS_DEGRADED_FINISH_WRAPPER_PATCH_V1 ===
{indent2}try:
{indent2}  _ci = data.get("ci_run_dir") or data.get("ci_dir") or ""
{indent2}  _final2, _reason2, _degraded2 = _vsp_guess_final_and_reason(_ci, data)
{indent2}  data["finish_reason"] = _reason2
{indent2}  data["degraded_tools"] = _degraded2
{indent2}  data["final"] = bool(_final2)
{indent2}except Exception:
{indent2}  if data.get("finish_reason") is None: data["finish_reason"] = "running"
{indent2}  if data.get("degraded_tools") is None: data["degraded_tools"] = None
{indent2}  if data.get("final") is None: data["final"] = False
{indent2}# === END VSP_STATUS_DEGRADED_FINISH_WRAPPER_PATCH_V1 ===
"""

# insert patch right AFTER the if-line
insert_at = wpos + mif.end()
new_block = block[:mif.end()] + "\n" + patch + block[mif.end():]
txt = txt[:wpos] + new_block + txt[wend:]

p.write_text(txt, encoding="utf-8")
print("[OK] patched wrapper to add finish_reason/degraded_tools/final")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
