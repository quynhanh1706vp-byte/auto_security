#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/bin/vsp_timeout_guard_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_rc143_${TS}"
echo "[BACKUP] $F.bak_rc143_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("/home/test/Data/SECURITY_BUNDLE/bin/vsp_timeout_guard_v1.sh")
s=p.read_text(encoding="utf-8", errors="ignore")

# make it robust: treat 143 (SIGTERM) as timeout too
s2 = s.replace(
    'if [ "$rc" = "124" ] || [ "$rc" = "137" ]; then',
    'if [ "$rc" = "124" ] || [ "$rc" = "137" ] || [ "$rc" = "143" ]; then'
)

if s2 == s:
    # fallback regex if formatting differs
    s2 = re.sub(
        r'if\s+\[\s*"\$rc"\s*=\s*"124"\s*\]\s*\|\|\s*\[\s*"\$rc"\s*=\s*"137"\s*\]\s*;\s*then',
        'if [ "$rc" = "124" ] || [ "$rc" = "137" ] || [ "$rc" = "143" ]; then',
        s
    )

p.write_text(s2, encoding="utf-8")
print("[OK] patched rc=143 as timeout")
PY

bash -n "$F" && echo "[OK] bash -n OK"
