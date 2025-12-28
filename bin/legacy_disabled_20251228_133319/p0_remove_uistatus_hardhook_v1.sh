#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rmhardhook_${TS}"
echo "[BACKUP] ${W}.bak_rmhardhook_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
start="# ===================== VSP_P0_UI_STATUS_HARDHOOK_V1 ====================="
end  ="# ===================== /VSP_P0_UI_STATUS_HARDHOOK_V1 ====================="
if start not in s or end not in s:
    print("[SKIP] hardhook markers not found")
    raise SystemExit(0)
pat=re.compile(re.escape(start)+r".*?"+re.escape(end), re.S)
s2=pat.sub("", s, count=1)
p.write_text(s2, encoding="utf-8")
print("[OK] removed hardhook block")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE]"
