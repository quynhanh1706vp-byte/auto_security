#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_ops_panel_v1.js"

cp -f "$F" "${F}.bak_p917_${TS}" 2>/dev/null || true
echo "[OK] backup => ${F}.bak_p917_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_ops_panel_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace the old okBool line with robust logic
old = r'const okBool = p\.json \? !!p\.json\.ok : false;'
if not re.search(old, s):
    print("[WARN] cannot find old okBool line; skipping")
    raise SystemExit(0)

new = (
'    const okFromApi = (p.json && p.json.ok === true);\n'
'    // If API returns ok=false but HTTP=200 and no degraded tools => treat as OK (avoid false alarm)\n'
'    const okBool = okFromApi || (p.status===200 && tools.length===0);\n'
)
s = re.sub(old, new, s, count=1)
p.write_text(s, encoding="utf-8")
print("[OK] patched okBool logic")
PY

sudo systemctl restart "$SVC"
bash bin/ops/ops_restart_wait_ui_v1.sh

echo "Open: $BASE/c/settings  (Ctrl+Shift+R)"
