#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="bin/vsp_ui_finalize_commercial_p6_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_${TS}"
echo "[BACKUP] $F.bak_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("bin/vsp_ui_finalize_commercial_p6_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")
s=s.replace(
  "node --check /home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_bundle_commercial_",
  "node --check /home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_bundle_commercial_v2.js"
)
# fix chmod line if it was broken/cut
s=s.replace(
  "chmod +x /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_finalize_commercial_p6_v1",
  "chmod +x /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_finalize_commercial_p6_v1.sh"
)
p.write_text(s, encoding="utf-8")
print("[OK] patched p6 finalize: nodecheck + chmod")
PY

bash -n "$F" && echo "[OK] bash -n"
