#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_read_degraded_${TS}"
echo "[BACKUP] $F.bak_read_degraded_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# 1) helper block (insert once)
if "VSP_STATUS_READ_DEGRADED_TOOLS_V1" not in txt:
    helper = r'''
# === VSP_STATUS_READ_DEGRADED_TOOLS_V1 ===
import json as _json
import os as _os
import time as _time
from pathlib import Path as _Path

def _vsp__safe_read_json_file(_p):
    try:
        return _json.loads(_Path(_p).read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        return None

def _vsp__read_degraded_tools_from_ci(_ci_run_dir):
    if not _ci_run_dir:
        return None
    _f = _Path(_ci_run_dir) / "degraded_tools.json"
    if not _f.exists():
        return None
    _d = _vsp__safe_read_json_file(_f)
    if isinstance(_d, dict) and isinstance(_d.get("items"), list):
        return _d.get("items")
    return _d

def _vsp__finish_reason_from_ci(_ci_run_dir):
    # conservative: only say completed if we see an explicit summary marker
    if not _ci_run_dir:
        return None
    _ci = _Path(_ci_run_dir)
    for _m in ("summary_unified.json", "SUMMARY.txt"):
        if (_ci / _m).exists():
            return "completed"
    _rlog = _ci / "runner.log"
    if _rlog.exists():
        _stall = int(_os.environ.get("VSP_STALL_SEC", "300"))
        try:
            _age = _time.time() - _rlog.stat().st_mtime
            if _age > _stall:
                return "stalled"
        except Exception:
            pass
    return "running"
# === END VSP_STATUS_READ_DEGRADED_TOOLS_V1 ===
'''
    # insert near top: after first flask import (best effort)
    m = re.search(r'^(from flask import .+)$', txt, flags=re.M)
    if m:
        i = m.end()
        txt = txt[:i] + "\n" + helper + "\n" + txt[i:]
    else:
        txt = helper + "\n" + txt

# 2) inject into wrapper (only in the V2_SAFE block)
if "VSP_DEMOAPP_STATUS_CONTRACT_V2_SAFE" not in txt:
    raise SystemExit("[ERR] cannot find VSP_DEMOAPP_STATUS_CONTRACT_V2_SAFE block to patch")

# find the place where wrapper normalizes ok/req_id (we inject right BEFORE ok-default)
pat = r'(\n[ \t]+)(if data\.get\("ok"\) is None:\s*data\["ok"\]\s*=\s*True)'
m = re.search(pat, txt)
if not m:
    raise SystemExit("[ERR] cannot locate ok-default line for injection")

indent = m.group(1)
inject = (
    f"{indent}# VSP_STATUS_READ_DEGRADED_TOOLS_V1 (auto)\n"
    f"{indent}try:\n"
    f"{indent}  _ci = data.get('ci_run_dir') or data.get('ci_dir') or data.get('run_dir')\n"
    f"{indent}  if _ci:\n"
    f"{indent}    if data.get('degraded_tools') is None:\n"
    f"{indent}      data['degraded_tools'] = _vsp__read_degraded_tools_from_ci(_ci)\n"
    f"{indent}    if data.get('finish_reason') is None:\n"
    f"{indent}      data['finish_reason'] = _vsp__finish_reason_from_ci(_ci)\n"
    f"{indent}    # tighten final: only true when completed marker exists\n"
    f"{indent}    if data.get('final') in (None, False) and data.get('finish_reason') == 'completed':\n"
    f"{indent}      data['final'] = True\n"
    f"{indent}except Exception:\n"
    f"{indent}  pass\n\n"
)

txt = txt[:m.start()] + inject + txt[m.start():]

p.write_text(txt, encoding="utf-8")
print("[OK] patched vsp_demo_app.py: run_status_v1 now includes degraded_tools + finish_reason (filesystem-derived)")
PY

python3 -m py_compile "$F" >/dev/null
echo "[OK] py_compile OK"

echo "[NEXT] restart UI: ./bin/start_8910_clean_v2.sh"
