#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

F="bin/p0_commercial_final_selfcheck_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_ridlatestpipe_${TS}"
echo "[BACKUP] ${F}.bak_ridlatestpipe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/p0_commercial_final_selfcheck_v1.sh")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_FIX_SELFCHK_RID_LATEST_PIPE_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Replace the broken pipe+heredoc python pattern with python -c
pat = re.compile(
    r'curl\s+-fsS\s+"\$BASE/api/vsp/rid_latest"\s*\|\s*python3\s+-\s+<<\'PY\'\s*\n'
    r'(?:.*\n)*?PY\s*\|\|\s*err\s+"rid_latest bad json"\s*\n',
    re.M
)

replacement = (
    f'curl -fsS "$BASE/api/vsp/rid_latest" | '
    f'python3 -c \'import sys,json; j=json.load(sys.stdin); '
    f'assert isinstance(j,dict); print("[OK] rid_latest =>", j.get("rid"))\' '
    f'|| err "rid_latest bad json"\n'
    f'# {MARK}\n'
)

s2, n = pat.subn(replacement, s, count=1)

if n == 0:
    # Fallback: patch the first occurrence of rid_latest line only
    s2 = re.sub(
        r'curl\s+-fsS\s+"\$BASE/api/vsp/rid_latest".*',
        replacement.strip("\n"),
        s,
        count=1
    )
    n = 1

p.write_text(s2, encoding="utf-8")
print("[OK] patched:", MARK, "replacements=", n)
PY

grep -n "rid_latest =>" -n "$F" | head -n 3 || true
echo "[OK] now rerun selfcheck:"
echo "bash /home/test/Data/SECURITY_BUNDLE/ui/bin/p0_commercial_final_selfcheck_v1.sh"
