#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runstatus_bootstrap_${TS}"
echo "[BACKUP] $F.bak_runstatus_bootstrap_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_RUN_STATUS_LAZY_BOOTSTRAP_STATE_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

m = re.search(r"^(\s*)def\s+run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find: def run_status_v1(req_id):")

indent = m.group(1) + "  "  # file của bạn nhìn giống style 2 spaces
inject = f"""{indent}# === {MARK} ===
{indent}try:
{indent}  from pathlib import Path
{indent}  import json, time, os
{indent}  _d = None
{indent}  try:
{indent}    _d = globals().get("_VSP_UIREQ_DIR", None)
{indent}  except Exception:
{indent}    _d = None
{indent}  _st = (Path(_d) / f"{{req_id}}.json") if _d else (Path("out_ci/ui_req_state") / f"{{req_id}}.json")
{indent}  if not _st.is_file():
{indent}    _st.parent.mkdir(parents=True, exist_ok=True)
{indent}    state0 = {{
{indent}      "request_id": req_id,
{indent}      "synthetic_req_id": True,
{indent}      "ci_run_dir": "",
{indent}      "runner_log": "",
{indent}      "ci_root_from_pid": None,
{indent}      "watchdog_pid": 0,
{indent}      "stage_sig": "0/0||0",
{indent}      "progress_pct": 0,
{indent}      "killed": False,
{indent}      "kill_reason": "",
{indent}      "final": False,
{indent}      "stall_timeout_sec": int(os.environ.get("VSP_STALL_TIMEOUT_SEC","600")),
{indent}      "total_timeout_sec": int(os.environ.get("VSP_TOTAL_TIMEOUT_SEC","7200")),
{indent}      "state_bootstrap_ts": int(time.time()),
{indent}    }}
{indent}    _st.write_text(json.dumps(state0, ensure_ascii=False, indent=2), encoding="utf-8")
{indent}except Exception:
{indent}  pass
{indent}# === END {MARK} ===
"""

# chèn ngay sau def line
insert_pos = m.end()
txt2 = txt[:insert_pos] + "\n" + inject + txt[insert_pos:]

p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
