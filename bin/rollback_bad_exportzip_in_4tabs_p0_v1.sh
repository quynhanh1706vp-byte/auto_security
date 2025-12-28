#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="templates/vsp_4tabs_commercial_v1.html"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "${T}.bak_rm_exportzip_${TS}"
echo "[BACKUP] ${T}.bak_rm_exportzip_${TS}"

python3 - <<'PY'
import re
from pathlib import Path
p=Path("templates/vsp_4tabs_commercial_v1.html")
s=p.read_text(encoding="utf-8", errors="replace")

# remove the injected block by marker
mark="VSP_RUNS_EXPORT_ZIP_BTN_P0_V1"
# remove <script> ... mark ... </script>
s2=re.sub(r'(?is)\n?<script>\s*/\*\s*'+re.escape(mark)+r'\s*\*/.*?</script>\s*\n?', "\n", s)

if s2==s:
    print("[WARN] marker not found; nothing removed")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] removed injected script block from", p)
PY
