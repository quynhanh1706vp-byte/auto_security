#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
ELOG="out_ci/ui_8910.error.log"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_import_time_${TS}"
echo "[BACKUP] ${F}.bak_import_time_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_IMPORT_TIME_P0_V2"
if MARK in s:
    print("[OK] already patched")
else:
    # Insert imports near top (after builtins MARK block is fine)
    ins = None
    m = re.search(r'(?m)^from vsp_demo_app import app as application\s*# gunicorn entrypoint\s*$', s)
    if m:
        ins = m.start()
    else:
        # fallback: after initial docstring
        ins = 0

    inject = (
        f"\n# {MARK}: required by WSGI wrapper (__call__) and cache-bust logic\n"
        "import time\n"
        "import os\n"
        f"# /{MARK}\n\n"
    )
    s = s[:ins] + inject + s[ins:]
    p.write_text(s, encoding="utf-8")
    print("[OK] injected import time/os")
PY

echo "== py_compile =="
python3 -m py_compile "$F"

echo "== truncate error log (NEW only) =="
mkdir -p out_ci
sudo truncate -s 0 "$ELOG" || true

echo "== restart =="
sudo systemctl restart "$SVC"
sleep 0.8

echo "== verify /runs now not 500 =="
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,25p'
