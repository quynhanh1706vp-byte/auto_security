#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="bin/p1_commercial_gate_selfcheck_p1_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_require_real_${TS}"
echo "[BACKUP] ${F}.bak_require_real_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/p1_commercial_gate_selfcheck_p1_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_REQUIRE_REAL_RUN_NOT_BACKFILLED_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Insert after "== 2) Runs API + RID ==" block (after RID is known)
hook = r'''
# VSP_P1_REQUIRE_REAL_RUN_NOT_BACKFILLED_V1
echo
echo "== 2b) Require real run (no backfill/demo) =="
if [ -n "${RID:-}" ] && [ "$RID" != "null" ]; then
  SUM="$(curl -sS "$BASE/api/vsp/run_file?rid=${RID}&name=reports%2Frun_gate_summary.json" || true)"
  if echo "$SUM" | jq -e . >/dev/null 2>&1; then
    DEG="$(echo "$SUM" | jq -r '.degraded // false')"
    VER="$(echo "$SUM" | jq -r '.verdict // ""')"
    NOTE="$(echo "$SUM" | jq -r '.note // ""')"
    if [ "$DEG" = "true" ] || [ "$VER" = "UNKNOWN" ] || echo "$NOTE" | grep -qi "backfilled"; then
      echo "[FAIL] latest run looks backfilled/demo or degraded: degraded=$DEG verdict=$VER note=$NOTE"
      exit 3
    else
      echo "[OK] run looks real: degraded=$DEG verdict=$VER"
    fi
  else
    echo "[WARN] cannot parse run_gate_summary.json as JSON (skipping real-run check)"
  fi
fi
'''

# Find a good anchor: right after the RID is printed OK
m = re.search(r'pass "latest RID=\$RID"\n', s)
if not m:
    print("[ERR] cannot find anchor 'pass \"latest RID=$RID\"'")
    raise SystemExit(2)

idx = m.end()
s2 = s[:idx] + hook + "\n" + s[idx:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected real-run requirement")
PY

bash -n bin/p1_commercial_gate_selfcheck_p1_v1.sh
echo "[OK] bash -n OK"
