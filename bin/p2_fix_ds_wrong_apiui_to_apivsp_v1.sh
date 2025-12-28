#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_data_source_tab_v3.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_apiui_${TS}"
echo "[BACKUP] ${F}.bak_fix_apiui_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_data_source_tab_v3.js")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) replace any hard-coded /api/ui/findings_v3... with /api/vsp/findings_page_v3
s2 = s
s2 = re.sub(r'(["\'])/api/ui/findings_v3\1', r'\1/api/vsp/findings_page_v3\1', s2)

# 2) also catch patterns like "/api/ui/findings_v3?" inside string concat
s2 = s2.replace("/api/ui/findings_v3?", "/api/vsp/findings_page_v3?")

# 3) tag marker
if "VSP_P2_FIX_APIUI_TO_APIVSP_V1" not in s2:
    s2 += "\n/* ===== VSP_P2_FIX_APIUI_TO_APIVSP_V1 ===== */\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched api/ui -> api/vsp in", p)
PY

echo "[OK] patched. Now restart service (non-interactive preferred)."
if sudo -n true 2>/dev/null; then
  sudo -n systemctl restart vsp-ui-8910.service
  echo "[OK] restarted"
else
  echo "[WARN] sudo -n not ready; run: sudo -v  (then restart service)"
fi

echo "[NEXT] Hard refresh browser (Ctrl+Shift+R) and check console:"
echo "  http://127.0.0.1:8910/data_source?severity=MEDIUM"
echo "  http://127.0.0.1:8910/data_source?severity=HIGH&q=codeql"
