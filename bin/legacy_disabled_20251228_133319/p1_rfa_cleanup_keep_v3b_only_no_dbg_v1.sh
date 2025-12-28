#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rfa_cleanup_${TS}"
echo "[BACKUP] ${W}.bak_rfa_cleanup_${TS}"

python3 - "$W" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

# remove older blocks V1/V2/V2FIX if present
blocks = [
  "VSP_P0_WSGIGW_RFA_WSGI_MW_PROMOTE_V1",
  "VSP_P0_WSGIGW_RFA_WSGI_MW_PROMOTE_V2_FORCE_DBG",
  "VSP_P0_WSGIGW_RFA_WSGI_MW_PROMOTE_V2_FORCE_DBG_FIX_V1",
  "VSP_P0_WSGIGW_RFA_AFTER_REQUEST_PROMOTE_V1",
]
for tag in blocks:
    start = s.find(f"# --- {tag} ---")
    if start >= 0:
        end = s.find(f"# --- /{tag} ---", start)
        if end >= 0:
            end = end + len(f"# --- /{tag} ---")
            s = s[:start] + "\n" + s[end:] + "\n"
        else:
            s = s[:start] + "\n"

# keep V3B but remove DBG/ERR headers lines (commercial quiet)
# (still keeps X-VSP-RFA-PROMOTE: v3)
s = re.sub(r'\n\s*_set_header\("X-VSP-RFA-PROMOTE-DBG".*?\)\s*', "\n", s)
s = re.sub(r'\n\s*_set_header\("X-VSP-RFA-PROMOTE-ERR".*?\)\s*', "\n", s)

p.write_text(s, encoding="utf-8")
print("[OK] cleaned V1/V2 blocks; kept V3B; removed DBG/ERR headers")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
