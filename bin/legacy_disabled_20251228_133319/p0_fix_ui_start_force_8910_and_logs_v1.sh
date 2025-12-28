#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p1_ui_8910_single_owner_start_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_force8910_${TS}"
echo "[BACKUP] ${F}.bak_force8910_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/p1_ui_8910_single_owner_start_v2.sh")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) harden PORT default to 8910 (common patterns)
s = re.sub(r'(?m)^\s*PORT=\$\{PORT:-8000\}\s*$', 'PORT=${PORT:-8910}', s)
s = re.sub(r'(?m)^\s*PORT="\$\{PORT:-8000\}"\s*$', 'PORT="${PORT:-8910}"', s)
s = re.sub(r'(?m)^\s*PORT=8000\s*$', 'PORT=8910', s)

# 2) replace any literal :8000 to :8910 (bind/check/kill)
s = s.replace(":8000", ":8910")

# 3) ensure gunicorn uses correct app + bind (best-effort)
s = s.replace("core.wsgi:application", "wsgi_vsp_ui_gateway:application")
s = re.sub(r'--bind\s+127\.0\.0\.1:\$\{PORT\}', '--bind 127.0.0.1:${PORT}', s)

# 4) force nohup redirect to boot log (avoid nohup.out)
# If script has a nohup gunicorn ... & without redirect, add redirect
lines = s.splitlines(True)
out=[]
for line in lines:
    if "nohup" in line and "gunicorn" in line and "nohup.out" not in line:
        # if already has > out_ci/ui_8910.boot.log keep it
        if "out_ci/ui_8910.boot.log" in line:
            out.append(line); continue
        # if line already redirects somewhere, keep it
        if ">" in line or "2>" in line:
            out.append(line); continue
        # inject redirect before trailing &
        if line.rstrip().endswith("&"):
            out.append(line.rstrip()[:-1] + " > out_ci/ui_8910.boot.log 2>&1 &\n")
        else:
            out.append(line.rstrip() + " > out_ci/ui_8910.boot.log 2>&1\n")
    else:
        out.append(line)
s2="".join(out)

p.write_text(s2, encoding="utf-8")
print("[OK] patched start script: PORT=8910, removed :8000, redirect nohup -> out_ci/ui_8910.boot.log")
PY

bash -n "$F"
echo "[OK] bash -n OK"

echo "== DEBUG: show any remaining 8000 refs (should be empty) =="
grep -n "8000" "$F" || true
