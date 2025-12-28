#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p1_ui_8910_single_owner_start_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_replace_nohup_${TS}"
echo "[BACKUP] ${F}.bak_replace_nohup_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/p1_ui_8910_single_owner_start_v2.sh")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

# locate the first nohup block and replace it
start = None
for i,l in enumerate(lines):
    if re.match(r'^\s*nohup\b', l):
        start = i
        break
if start is None:
    raise SystemExit("[ERR] cannot find nohup block")

end = None
for j in range(start, min(start+120, len(lines))):
    if re.search(r'\&\s*$', lines[j]) or re.match(r'^\s*\&\s*$', lines[j]):
        end = j
        break
if end is None:
    raise SystemExit("[ERR] cannot find end of nohup block (&)")

replacement = [
    '  # VSP_P0_FORCE_NOHUP_BIND_8910_V1\n',
    '  PORT=8910\n',
    '  GUNI="./.venv/bin/gunicorn"\n',
    '  [ -x "$GUNI" ] || GUNI="$(command -v gunicorn || true)"\n',
    '  [ -n "${GUNI}" ] || { echo "[ERR] gunicorn not found"; exit 2; }\n',
    '  echo "[DBG] gunicorn=$GUNI"\n',
    '  echo "[DBG] bind=127.0.0.1:${PORT}"\n',
    '  # hard-bind 8910 + force logs into out_ci (no nohup.out)\n',
    '  nohup "$GUNI" wsgi_vsp_ui_gateway:application \\\n',
    '    --workers 2 \\\n',
    '    --worker-class gthread \\\n',
    '    --threads 4 \\\n',
    '    --timeout 60 \\\n',
    '    --graceful-timeout 15 \\\n',
    '    --chdir /home/test/Data/SECURITY_BUNDLE/ui \\\n',
    '    --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \\\n',
    '    --bind 127.0.0.1:8910 \\\n',
    '    --access-logfile out_ci/ui_8910.access.log \\\n',
    '    --error-logfile out_ci/ui_8910.error.log \\\n',
    '    > out_ci/ui_8910.boot.log 2>&1 &\n',
]

new_lines = lines[:start] + replacement + lines[end+1:]
p.write_text("".join(new_lines), encoding="utf-8")
print(f"[OK] replaced nohup block lines {start+1}-{end+1} with forced bind 8910")
PY

bash -n "$F"
echo "[OK] bash -n OK"
