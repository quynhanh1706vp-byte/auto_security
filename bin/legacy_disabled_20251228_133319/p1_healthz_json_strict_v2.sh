#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

TS="$(date +%Y%m%d_%H%M%S)"

patch_file(){
  local F="$1"
  [ -f "$F" ] || return 0
  if grep -q "VSP_P1_HEALTHZ_JSON_STRICT_V2" "$F"; then
    echo "[OK] already patched: $F"
    return 0
  fi

  cp -f "$F" "${F}.bak_healthz_strict_${TS}"
  echo "[BACKUP] ${F}.bak_healthz_strict_${TS}"

  python3 - <<PY
from pathlib import Path
import re

p=Path("$F")
s=p.read_text(encoding="utf-8", errors="replace")

# ensure imports (safe if duplicates)
if "import os" not in s: s="import os\\n"+s
if "import time" not in s: s="import time\\n"+s
if "import socket" not in s: s="import socket\\n"+s
if "from flask import jsonify" not in s:
    # put near top; ok if flask already imported elsewhere
    s = s.replace("from flask import", "from flask import jsonify, ", 1) if "from flask import" in s else ("from flask import jsonify\\n"+s)

# find the exact 'app = Flask(...)' line (multiline-safe)
m = re.search(r'(?m)^\\s*app\\s*=\\s*Flask\\s*\\(.*\\)\\s*$', s)
if not m:
    # more tolerant: match 'app = Flask(' without closing ')'
    m = re.search(r'(?m)^\\s*app\\s*=\\s*Flask\\s*\\(.*$', s)

if not m:
    raise SystemExit(f"[ERR] cannot find 'app = Flask(...)' in {p}")

# insert right after that line
line_end = s.find("\\n", m.end())
insert_at = (line_end+1) if line_end!=-1 else len(s)

block = r'''
# --- VSP_P1_HEALTHZ_JSON_STRICT_V2 ---
@app.get("/healthz")
def vsp_healthz_json_strict_v2():
    # STRICT JSON: never render templates, never redirect
    return jsonify({
        "ui_up": True,
        "ts": int(time.time()),
        "pid": os.getpid(),
        "host": socket.gethostname(),
        "contract": "P1_HEALTHZ_V2"
    }), 200
# --- /VSP_P1_HEALTHZ_JSON_STRICT_V2 ---

'''
s2 = s[:insert_at] + block + s[insert_at:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected strict /healthz into", p)
PY

  python3 -m py_compile "$F" && echo "[OK] py_compile OK: $F"
}

# patch gateway first (most likely served by gunicorn), then fallback
patch_file "wsgi_vsp_ui_gateway.py"
patch_file "vsp_demo_app.py"

echo "[OK] patched. Restart service then verify:"
echo "  curl -i http://127.0.0.1:8910/healthz"
