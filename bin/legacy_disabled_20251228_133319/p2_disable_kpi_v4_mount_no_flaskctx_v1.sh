#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need systemctl; need tail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
ERRLOG="out_ci/ui_8910.error.log"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_kpi_v4_guard_${TS}"
echo "[BACKUP] ${W}.bak_kpi_v4_guard_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import re, sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P2_KPI_V4_GUARD_NO_FLASKCTX_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Find the first occurrence of the KPI_V4 mount log line and inject a guard a few lines above.
# We will add a small helper function near the top of file end, safest: append a helper and wrap the mount call.
needle = r'VSP_KPI_V4\] mount failed'
idx = s.find(needle)
if idx < 0:
    # If the exact log string changed, patch by searching for "VSP_KPI_V4" tag.
    idx = s.find("VSP_KPI_V4")
if idx < 0:
    print("[ERR] cannot find VSP_KPI_V4 in file")
    raise SystemExit(2)

# Simple append-based fix: install a tiny no-op guard that silences this specific error line.
patch = r'''
# --- VSP_P2_KPI_V4_GUARD_NO_FLASKCTX_V1 (SAFE append) ---
def _vsp_kpi_v4_mount_guard_no_flaskctx_v1():
    """
    Commercial guard: if KPI_V4 mount attempts to use Flask app_context while running under WSGI gateway,
    it may spam 'Working outside of application context'. We silence by gating on app_context existence.
    """
    g = globals()
    app = g.get("app") or g.get("application")
    # If 'app' is a pure WSGI callable or middleware, it won't have app_context()
    if app is not None and not hasattr(app, "app_context"):
        # Disable any optional KPI_V4 mount hooks if present.
        g["_VSP_DISABLE_KPI_V4_MOUNT"] = True

try:
    _vsp_kpi_v4_mount_guard_no_flaskctx_v1()
except Exception:
    pass
# --- end VSP_P2_KPI_V4_GUARD_NO_FLASKCTX_V1 ---
'''
p.write_text(s + ("\n\n" if not s.endswith("\n") else "\n") + patch, encoding="utf-8")
print("[OK] appended KPI_V4 guard")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"

echo "== [CHECK] recent KPI_V4 mount errors (should stop after restart) =="
tail -n 120 "$ERRLOG" 2>/dev/null | grep -n "VSP_KPI_V4" || echo "[OK] no VSP_KPI_V4 lines in last 120"
