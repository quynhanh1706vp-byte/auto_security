#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_kpiappctx_${TS}"
echo "[BACKUP] ${WSGI}.bak_kpiappctx_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_KPI_V4"
PATCH = "VSP_P0_KPI_V4_APPCTX_RETRY_V1"

if PATCH in s:
    print("[OK] already patched:", PATCH)
    raise SystemExit(0)

# Insert helper once, near first VSP_KPI_V4 occurrence
idx = s.find(MARK)
if idx < 0:
    raise SystemExit("[ERR] cannot find VSP_KPI_V4 in wsgi")

helper = r'''
# ===================== VSP_P0_KPI_V4_APPCTX_RETRY_V1 =====================
def _vsp_find_real_flask_app_v1():
    try:
        # heuristic: Flask app has route + app_context + url_map
        for v in list(globals().values()):
            if hasattr(v, "app_context") and hasattr(v, "route") and hasattr(v, "url_map"):
                return v
    except Exception:
        pass
    return None

def _vsp_try_in_appctx_v1(fn, why="kpi_v4"):
    try:
        return fn()
    except Exception as e:
        msg = str(e)
        if "application context" not in msg and "app context" not in msg:
            raise
        app = _vsp_find_real_flask_app_v1()
        if not app:
            print(f"[{why}] appctx retry skipped: no real Flask app found; err={repr(e)}")
            raise
        try:
            with app.app_context():
                print(f"[{why}] retry in app_context OK")
                return fn()
        except Exception as e2:
            print(f"[{why}] retry in app_context FAILED: {repr(e2)}")
            raise
# ===================== /VSP_P0_KPI_V4_APPCTX_RETRY_V1 =====================
'''

# Put helper block just before first KPI marker line (keep imports/structure intact)
s2 = s[:idx] + helper + "\n" + s[idx:]

# Now wrap the KPI_V4 mount try-block by converting:
#    except Exception as e: print("[VSP_KPI_V4] mount failed: ...")
# into: retry if appctx error
# We do a conservative patch: if we see the specific log "mount failed:" we inject a retry call right before printing.
pat = r'(\[VSP_KPI_V4\]\s*mount failed:\s*)'
if re.search(pat, s2) is None:
    # still keep helper; maybe mount uses different text
    p.write_text(s2, encoding="utf-8")
    print("[WARN] KPI mount-failed signature not found; helper injected only.")
    print("[OK] patched:", PATCH)
    raise SystemExit(0)

# Inject a retry hook: if mount failed due to appctx, call the same mount function again inside appctx.
# This relies on the mount happening inside a try: ... except Exception as e: block in the same scope.
inj = r'''
# -- %s: retry mount inside app_context when needed --
try:
    _vsp_try_in_appctx_v1(lambda: (_vsp_kpi_v4_mount_v1() if "_vsp_kpi_v4_mount_v1" in globals() else None), why="VSP_KPI_V4")
except Exception:
    pass
''' % PATCH

# Place injection near the first occurrence of the failure log print line to keep it local.
s3 = re.sub(r'(?m)^(.*\bprint\(\s*"\[VSP_KPI_V4\]\s*mount failed:.*$)', inj + r'\n\1', s2, count=1)

p.write_text(s3, encoding="utf-8")
print("[OK] patched:", PATCH)
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== CHECK recent KPI log =="
journalctl -u "$SVC" --no-pager -n 120 | egrep -i "VSP_KPI_V4|app_context" | tail -n 30 || true
