#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_data_source_pagination_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_findingsv3_${TS}"
echo "[BACKUP] ${F}.bak_fix_findingsv3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_data_source_pagination_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
if "VSP_P2_FIX_DS_PAGINATION_FINDINGS_V3_TO_PAGE_V3_V1" in s:
    print("[OK] already patched")
    raise SystemExit(0)

s2=s
s2=re.sub(r'(?m)(API_BASE\s*=\s*[\'"])\/api\/ui\/findings_v3([\'"])',
          r'\1/api/vsp/findings_page_v3\2', s2)

# also patch any inline fetch("/api/ui/findings_v3") variants
s2=s2.replace("/api/ui/findings_v3", "/api/vsp/findings_page_v3")

if s2==s:
    print("[WARN] no change made (pattern not found?)")
else:
    s2="/* ===== VSP_P2_FIX_DS_PAGINATION_FINDINGS_V3_TO_PAGE_V3_V1 ===== */\n"+s2
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched", p)
PY

echo "[OK] restart service (to bump asset_v if you use runtime stamp)"
sudo systemctl restart vsp-ui-8910.service || true

echo "[NEXT] hard refresh: http://127.0.0.1:8910/data_source?severity=MEDIUM"
