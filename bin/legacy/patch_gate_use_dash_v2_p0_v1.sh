#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="bin/vsp_commercial_autofix_gate_p2_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_dashv2_${TS}"
echo "[BACKUP] $F.bak_dashv2_${TS}"

# replace health URL list + dash snapshot to prefer v2
python3 - <<'PY'
from pathlib import Path
p=Path("bin/vsp_commercial_autofix_gate_p2_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

s=s.replace(
  '"$BASE/api/vsp/dashboard_commercial_v1"',
  '"$BASE/api/vsp/dashboard_commercial_v2"\n  "$BASE/api/vsp/dashboard_commercial_v1"',
  1
)

s=s.replace(
  'curl -sS "$BASE/api/vsp/dashboard_commercial_v1?ts=$TS" | tee "$OUT/dashboard_commercial_v1.json"',
  'curl -sS "$BASE/api/vsp/dashboard_commercial_v2?ts=$TS" | tee "$OUT/dashboard_commercial_v2.json" || true\ncurl -sS "$BASE/api/vsp/dashboard_commercial_v1?ts=$TS" | tee "$OUT/dashboard_commercial_v1.json"',
  1
)

p.write_text(s, encoding="utf-8")
print("[OK] patched gate to prefer dashboard_commercial_v2")
PY

bash -n "$F"
echo "[OK] bash -n"
