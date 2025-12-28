#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE

F="bin/run_all_tools_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_skip_legacy_kics_${TS}"
echo "[BACKUP] $F.bak_skip_legacy_kics_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/run_all_tools_v2.sh")
s = p.read_text(encoding="utf-8", errors="ignore")

# 1) after commercial run_kics_v2.sh call, mark done
if "VSP_KICS_COMMERCIAL_DONE" not in s:
    s2, n = re.subn(
        r'(\s*"\$ROOT/bin/run_kics_v2\.sh"\s+"\$\{KICS_OUT_DIR\}"\s+"\$\{KICS_SRC\}"\s*\|\|\s*true\s*\n)',
        r'\1  export VSP_KICS_COMMERCIAL_DONE=1\n',
        s,
        count=1
    )
    if n == 0:
        # fallback: mark after any run_kics_v2.sh line
        s2, n2 = re.subn(
            r'(\s*run_kics_v2\.sh[^\n]*\n)',
            r'\1  export VSP_KICS_COMMERCIAL_DONE=1\n',
            s,
            count=1
        )
        s = s2
    else:
        s = s2

# 2) modify legacy KICS condition to skip when commercial done
# find the legacy "if [ ! -s "$RUN_DIR/kics/kics_results.json" ]" and add flag gate
s, n = re.subn(
    r'if\s+\[\s*!\s+-s\s+"\$RUN_DIR/kics/kics_results\.json"\s*\]\s*;\s*then',
    r'if [ "${VSP_KICS_COMMERCIAL_DONE:-0}" != "1" ] && [ ! -s "$RUN_DIR/kics/kics_results.json" ]; then',
    s,
    count=1
)

p.write_text(s, encoding="utf-8")
print(f"[OK] patched legacy_kics_gate={n}")
PY

bash -n "$F" && echo "[OK] bash -n OK"
echo "== check markers =="
grep -nE "VSP_KICS_COMMERCIAL_DONE|kics_results\.json" "$F" | head -n 60
