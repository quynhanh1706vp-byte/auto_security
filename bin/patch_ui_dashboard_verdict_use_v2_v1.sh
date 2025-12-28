#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/dashboard_render.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_verdict_usev2_${TS}"
echo "[BACKUP] $F.bak_verdict_usev2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/dashboard_render.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# Replace only inside our injected block if present
s2 = s.replace("`/api/vsp/gate_policy_v1/${encodeURIComponent(rid)}`",
              "`/api/vsp/gate_policy_v2/${encodeURIComponent(rid)}`")

# If still v1 exists somewhere else, add fallback logic (light touch)
if s2 == s:
    # nothing replaced; do a minimal safe insert: try v2 then v1
    s2 = re.sub(
        r"const\s+gpRes\s*=\s*await\s+fetch\((`/api/vsp/gate_policy_v1/\$\{encodeURIComponent\(rid\)\}`)\);\s*\n\s*if\s*\(!gpRes\.ok\)\s*return;",
        "let gpRes = await fetch(`/api/vsp/gate_policy_v2/${encodeURIComponent(rid)}`);\n      if (!gpRes.ok) gpRes = await fetch(`/api/vsp/gate_policy_v1/${encodeURIComponent(rid)}`);\n      if (!gpRes.ok) return;",
        s2
    )

p.write_text(s2, encoding="utf-8")
print("[OK] patched dashboard_render.js to use gate_policy_v2")
PY

echo "[NEXT] hard refresh browser (Ctrl+Shift+R)"
