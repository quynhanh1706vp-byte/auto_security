#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p1_ui_8910_single_owner_start_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_maxreq_${TS}"
echo "[BACKUP] ${F}.bak_maxreq_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/p1_ui_8910_single_owner_start_v2.sh")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_GUNICORN_MAXREQ_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Heuristic: inject flags right after "gunicorn" invocation line chunk
# We'll append flags if not present.
if "--max-requests" in s:
    print("[OK] already has --max-requests")
    raise SystemExit(0)

# Try to locate the gunicorn command line (first occurrence of 'gunicorn ' in script)
idx = s.find("gunicorn ")
if idx < 0:
    print("[ERR] cannot find 'gunicorn ' in start script")
    raise SystemExit(2)

# Insert flags after 'gunicorn ...' line block by replacing the first occurrence of '--threads' or '--worker-class' anchor
anchors = ["--worker-class", "--threads", "--timeout", "--bind"]
pos = -1
for a in anchors:
    pos = s.find(a, idx)
    if pos >= 0:
        break
if pos < 0:
    print("[ERR] cannot find an anchor flag to inject")
    raise SystemExit(2)

inject = f"\n  # {MARK}\n  --max-requests 200 \\\n  --max-requests-jitter 50 \\\n"
s2 = s[:pos] + inject + s[pos:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected max-requests flags:", MARK)
PY

bash -n "$F"
echo "[OK] bash -n OK"
