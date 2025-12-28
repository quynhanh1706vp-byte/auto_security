#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p1_ui_8910_single_owner_start_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_unset_guniargs_${TS}"
echo "[BACKUP] ${F}.bak_unset_guniargs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/p1_ui_8910_single_owner_start_v2.sh")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_UNSET_GUNICORN_CMD_ARGS_V1"
if MARK in s:
    print("[OK] already injected:", MARK)
    raise SystemExit(0)

lines=s.splitlines(True)
out=[]
inserted=False

for i,l in enumerate(lines):
    out.append(l)
    # chèn ngay sau dòng PORT=...
    if (not inserted) and re.match(r'^\s*PORT=', l):
        out.append(f'\n# {MARK}\n')
        out.append('echo "[DBG] before: GUNICORN_CMD_ARGS=${GUNICORN_CMD_ARGS:-<empty>}"\n')
        out.append('unset GUNICORN_CMD_ARGS || true\n')
        out.append('export GUNICORN_CMD_ARGS=""\n')
        out.append('echo "[DBG] after : GUNICORN_CMD_ARGS=${GUNICORN_CMD_ARGS:-<empty>}"\n\n')
        inserted=True

p.write_text("".join(out), encoding="utf-8")
print("[OK] injected:", MARK, "inserted=", inserted)
PY

bash -n "$F"
echo "[OK] bash -n OK"
