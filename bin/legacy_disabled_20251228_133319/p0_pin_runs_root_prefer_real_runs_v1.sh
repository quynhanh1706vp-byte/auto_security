#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need bash

F="bin/p1_ui_8910_single_owner_start_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_pin_runs_root_${TS}"
echo "[BACKUP] ${F}.bak_pin_runs_root_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/p1_ui_8910_single_owner_start_v2.sh")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_PIN_RUNS_ROOT_PREFER_REAL_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# insert near environment setup (before starting gunicorn)
# find first occurrence of gunicorn invocation marker
m = re.search(r'(?m)^\s*GUNICORN\s*=|^\s*gunicorn=', s)
ins = m.start() if m else 0

inject = f'''# ==== {MARK} ====
# Pin runs roots to real SECURITY_BUNDLE runs (avoid BOSS_BUNDLE taking rid_latest)
export VSP_RUNS_ROOTS="${{VSP_RUNS_ROOTS:-/home/test/Data/SECURITY_BUNDLE/out}}"
export VSP_RUNS_CACHE_TTL="${{VSP_RUNS_CACHE_TTL:-2}}"
export VSP_RUNS_SCAN_CAP="${{VSP_RUNS_SCAN_CAP:-500}}"
# ==== /{MARK} ====

'''

s = s[:ins] + inject + s[ins:]
p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

bash -n "$F"
echo "[OK] bash -n OK: $F"

rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh

# smoke
bin/p1_diag_runs_contract_v1.sh || true
bin/p0_commercial_selfcheck_ui_v1.sh || true
