#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/ui/bin/p2_ui_feature_gap_check_v1b.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_cwd_v1c_${TS}"
echo "[BACKUP] ${F}.bak_cwd_v1c_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/bin/p2_ui_feature_gap_check_v1b.sh")
s = p.read_text(encoding="utf-8", errors="replace")

# Ensure we cd to UI root regardless of where script is executed
# Insert after shebang + set -euo pipefail (first occurrence)
if "VSP_P2_FEATURE_GAP_CWD_FIX_V1C" not in s:
    s = re.sub(
        r'(^#!/usr/bin/env bash\s*\nset -euo pipefail\s*\n)',
        r'\1\n# VSP_P2_FEATURE_GAP_CWD_FIX_V1C\nROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\ncd "$ROOT"\n\n',
        s,
        count=1,
        flags=re.M
    )

p.write_text(s, encoding="utf-8")
print("[OK] patched cwd fix marker => VSP_P2_FEATURE_GAP_CWD_FIX_V1C")
PY

echo
echo "== QUICK RUN (from anywhere) =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/p2_ui_feature_gap_check_v1b.sh | tail -n 80
