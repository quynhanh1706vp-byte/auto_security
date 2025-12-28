#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_VSP5_FORCE_MW_LAST_V1"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_force_mw_last_${TS}"
echo "[BACKUP] ${W}.bak_force_mw_last_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
mark="VSP_P1_VSP5_FORCE_MW_LAST_V1"
if mark in s:
    print("[OK] already patched:", mark); raise SystemExit(0)

# Append at end to ensure it's the last wrapper
add = f"""

# ===================== {mark} =====================
try:
    application
    _vsp5_dash_only_mw
    application = _vsp5_dash_only_mw(application)
except Exception:
    pass
# ===================== /{mark} =====================
"""
s2 = s.rstrip() + "\n" + add
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok:", mark)
PY

systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
echo "[DONE] forced /vsp5 dash-only mw to be last wrapper."
