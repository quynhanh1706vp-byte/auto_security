#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_bootstrap_on_reqid_${TS}"
echo "[BACKUP] $F.bak_bootstrap_on_reqid_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_BOOTSTRAP_ON_REQID_CREATION_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Find lines that assign a variable to something containing VSP_UIREQ_
# Examples:
#   req_id = f"VSP_UIREQ_..."
#   request_id = "VSP_UIREQ_" + ...
assign_re = re.compile(r"^(\s*)(\w+)\s*=\s*.*VSP_UIREQ_", re.M)

matches = list(assign_re.finditer(txt))
if not matches:
    raise SystemExit("[ERR] cannot find any assignment containing VSP_UIREQ_")

inj_tpl = r'''
@@IND@@# === @@MARK@@ ===
@@IND@@try:
@@IND@@  from pathlib import Path
@@IND@@  import json, time, os
@@IND@@  _rid = str(@@VAR@@)
@@IND@@  # write to the SAME dir that run_status reads
@@IND@@  _d = None
@@IND@@  try:
@@IND@@    _d = globals().get("_VSP_UIREQ_DIR", None)
@@IND@@  except Exception:
@@IND@@    _d = None
@@IND@@  st_dir = Path(_d) if _d else (Path(__file__).resolve().parents[1] / "ui" / "out_ci" / "uireq_v1")
@@IND@@  st_dir.mkdir(parents=True, exist_ok=True)
@@IND@@  st_path = st_dir / (str(_rid) + ".json")
@@IND@@  if not st_path.is_file():
@@IND@@    st = {
@@IND@@      "request_id": _rid,
@@IND@@      "synthetic_req_id": True,
@@IND@@      "ci_run_dir": "",
@@IND@@      "runner_log": "",
@@IND@@      "ci_root_from_pid": None,
@@IND@@      "watchdog_pid": 0,
@@IND@@      "stage_sig": "0/0||0",
@@IND@@      "progress_pct": 0,
@@IND@@      "killed": False,
@@IND@@      "kill_reason": "",
@@IND@@      "final": False,
@@IND@@      "stall_timeout_sec": int(os.environ.get("VSP_STALL_TIMEOUT_SEC","600")),
@@IND@@      "total_timeout_sec": int(os.environ.get("VSP_TOTAL_TIMEOUT_SEC","7200")),
@@IND@@      "state_bootstrap_ts": int(time.time()),
@@IND@@    }
@@IND@@    st_path.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
@@IND@@    print("[@@MARK@@] wrote", st_path)
@@IND@@except Exception as e:
@@IND@@  try:
@@IND@@    print("[@@MARK@@] FAILED:", e)
@@IND@@  except Exception:
@@IND@@    pass
@@IND@@# === END @@MARK@@ ===
'''

# Insert after FIRST assignment (đủ để bootstrap)
m = matches[0]
indent, var = m.group(1), m.group(2)
line_end = txt.find("\n", m.end())
if line_end == -1:
    line_end = len(txt)

inject = (inj_tpl
          .replace("@@IND@@", indent)
          .replace("@@VAR@@", var)
          .replace("@@MARK@@", MARK))

txt2 = txt[:line_end+1] + inject + "\n" + txt[line_end+1:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK, "after var =", var, "at line", txt[:m.start()].count("\n")+1)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
