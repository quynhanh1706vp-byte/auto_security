#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/bin/vsp_timeout_guard_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_nomulti_${TS}"
echo "[BACKUP] $F.bak_nomulti_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("/home/test/Data/SECURITY_BUNDLE/bin/vsp_timeout_guard_v1.sh")
s=p.read_text(encoding="utf-8", errors="ignore")

# 1) treat rc=130 as timeout too (optional, safe)
s = s.replace(
    'if [ "$rc" = "124" ] || [ "$rc" = "137" ] || [ "$rc" = "143" ]; then',
    'if [ "$rc" = "124" ] || [ "$rc" = "137" ] || [ "$rc" = "143" ] || [ "$rc" = "130" ]; then'
)

# 2) if TIMEOUT marker exists, skip writing RC marker
pat = r'if \[ "\$rc" != "0" \]; then'
rep = 'if [ "$rc" != "0" ]; then\n  # commercial: avoid double markers when timeout already recorded\n  if [ -f "$RUN_DIR/degraded/${TOOL}_TIMEOUT.txt" ]; then\n    exit 0\n  fi'
s2, n = re.subn(pat, rep, s, count=1)

p.write_text(s2, encoding="utf-8")
print(f"[OK] patched_nonzero_block={n}")
PY

bash -n "$F" && echo "[OK] bash -n OK"
