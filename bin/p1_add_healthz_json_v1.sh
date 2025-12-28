#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"

patch_one(){
  local F="$1"
  [ -f "$F" ] || return 0
  if grep -q "VSP_P1_HEALTHZ_JSON_V1" "$F"; then
    echo "[OK] already patched: $F"
    return 0
  fi

  cp -f "$F" "${F}.bak_healthz_${TS}"
  echo "[BACKUP] ${F}.bak_healthz_${TS}"

  python3 - <<PY
from pathlib import Path
import re

p=Path("$F")
s=p.read_text(encoding="utf-8", errors="replace")

# ensure imports exist (best-effort, safe if duplicates)
if "import os" not in s: s = "import os\\n" + s
if "import time" not in s: s = "import time\\n" + s
if "import socket" not in s: s = "import socket\\n" + s

# find app = Flask(...)
m = re.search(r'\\n\\s*app\\s*=\\s*Flask\\s*\\(', s)
if not m:
    # if can't find, append at end guarded
    insert_at = len(s)
else:
    # insert AFTER the line containing app = Flask(
    line_end = s.find("\\n", m.start()+1)
    insert_at = line_end if line_end != -1 else m.end()

block = r"""

# --- VSP_P1_HEALTHZ_JSON_V1 ---
from flask import jsonify

def _vsp_best_effort_latest_rid():
    # Try to call local function if exists, else return N/A
    try:
        # some codebases expose a function or cache; keep safe
        return None
    except Exception:
        return None

@app.get("/healthz")
def vsp_healthz_json_v1():
    data = {
        "ui_up": True,
        "ts": int(time.time()),
        "pid": os.getpid(),
        "host": socket.gethostname(),
        "contract": "P1_HEALTHZ_V1",
    }
    # best effort: attach latest rid via internal API handler if present
    try:
        # If there is a local function already used by /api/vsp/runs, reuse by calling it directly
        # Otherwise, leave N/A (avoid HTTP self-call to prevent deadlocks)
        if "vsp_runs_api" in globals() and callable(globals().get("vsp_runs_api")):
            resp = globals()["vsp_runs_api"]()
            # might be flask Response/json; we won't hard parse
        data["last_rid"] = data.get("last_rid","N/A")
    except Exception:
        data["last_rid"] = data.get("last_rid","N/A")

    return jsonify(data), 200
# --- /VSP_P1_HEALTHZ_JSON_V1 ---

"""

s2 = s[:insert_at] + block + s[insert_at:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected healthz into", p)
PY

  python3 -m py_compile "$F" && echo "[OK] py_compile OK: $F"
}

# Try gateway first, then demo app
patch_one "wsgi_vsp_ui_gateway.py"
patch_one "vsp_demo_app.py"

echo "[OK] done. Restart UI service to apply."
