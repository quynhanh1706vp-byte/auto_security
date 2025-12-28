#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_KPI_V4_WRAP_APP_CONTEXT_V1"
cp -f "$F" "${F}.bak_kpictx_${TS}"
echo "[BACKUP] ${F}.bak_kpictx_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")
MARK="VSP_P2_KPI_V4_WRAP_APP_CONTEXT_V1"
if MARK in s:
    print("[OK] already patched"); sys.exit(0)

# Heuristic: find the log line marker and wrap the block following it if it's inside a try:
# We'll simply add a safe helper that reruns KPI mount under app_context at the end.
inject = f"""
# ===================== {MARK} =====================
def _vsp_kpi_v4_retry_with_app_context():
    try:
        # pick real flask app object
        g = globals()
        appx = None
        for _, v in list(g.items()):
            if v is None: 
                continue
            if hasattr(v, "app_context") and hasattr(v, "url_map") and hasattr(v, "add_url_rule"):
                appx = v
                break
        if appx is None:
            return False
        # if a KPI mount function exists, call it inside context
        fn = g.get("_mount_kpi_v4") or g.get("mount_kpi_v4") or g.get("vsp_kpi_v4_mount")
        if callable(fn):
            with appx.app_context():
                fn(appx)
            print("[VSP_KPI_V4] retry mount under app_context OK")
            return True
        return False
    except Exception as e:
        print("[VSP_KPI_V4] retry mount under app_context failed:", repr(e))
        return False

_vsp_kpi_v4_retry_with_app_context()
# ===================== /{MARK} =====================
"""
p.write_text(s + "\n\n" + inject + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] check journal: journalctl -u $SVC -n 60 --no-pager | grep -n 'KPI_V4' -n"
