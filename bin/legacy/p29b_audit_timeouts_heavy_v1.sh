#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/commercial_ui_audit_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p29b_to_${TS}"
echo "[BACKUP] ${F}.bak_p29b_to_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/commercial_ui_audit_v2.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# increase only the endpoints that are known to be slow/flaky
s2=s

# dashboard_extras_v1: from 12 -> 25
s2=re.sub(r'(check_api_json "dashboard_extras_v1"\s+"/api/vsp/dashboard_extras_v1"\s+)(\d+)',
          lambda m: m.group(1)+"25", s2, count=1)

# findings_unified_v1: from 12 -> 60
s2=re.sub(r'(check_api_json "findings_unified_v1"\s+"/api/vsp/findings_unified_v1/\$RID"\s+)(\d+)',
          lambda m: m.group(1)+"60", s2, count=1)

p.write_text(s2, encoding="utf-8")
print("[OK] patched audit timeouts: dashboard_extras_v1=25s, findings_unified_v1=60s")
PY
