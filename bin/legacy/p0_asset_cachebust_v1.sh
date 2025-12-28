#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
TPL="templates/vsp_5tabs_enterprise_v2.html"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_assetv_${TS}"
cp -f "$TPL" "${TPL}.bak_assetv_${TS}"
echo "[BACKUP] ${APP}.bak_assetv_${TS}"
echo "[BACKUP] ${TPL}.bak_assetv_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time, textwrap, py_compile

APP = Path("vsp_demo_app.py")
s = APP.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_ASSET_V_CTX_V1"
if MARK not in s:
    # inject near end (safe)
    block = textwrap.dedent(r"""
    # ===================== VSP_P0_ASSET_V_CTX_V1 =====================
    import time as _vsp_time
    try:
        _VSP_ASSET_V = str(int(_vsp_time.time()))  # stable per service restart
    except Exception:
        _VSP_ASSET_V = ""

    @app.context_processor
    def _vsp_ctx_asset_v():
        # expose asset_v for templates (cache-bust)
        return {"asset_v": _VSP_ASSET_V}
    # ===================== /VSP_P0_ASSET_V_CTX_V1 =====================
    """).strip() + "\n"
    s = s.rstrip() + "\n\n" + block
    APP.write_text(s, encoding="utf-8")
    py_compile.compile(str(APP), doraise=True)
    print("[OK] injected", MARK)
else:
    print("[OK] already has", MARK)
PY

python3 - <<'PY'
from pathlib import Path
import re

TPL = Path("templates/vsp_5tabs_enterprise_v2.html")
t = TPL.read_text(encoding="utf-8", errors="replace")

# patch only the specific JS src line if not already has ?v=
pat = r'(/static/js/vsp_data_source_charts_v1\.js)(?!\?v=)'
rep = r'/static/js/vsp_data_source_charts_v1.js?v={{ asset_v|default("") }}'

t2, n = re.subn(pat, rep, t)
if n:
    TPL.write_text(t2, encoding="utf-8")
    print("[OK] patched template cache-bust, replacements=", n)
else:
    print("[OK] template already cache-busted or src not found")
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== smoke =="
curl -sS "$BASE/vsp5" | head -n 8
echo
echo "== grep script src (should contain ?v=) =="
curl -sS "$BASE/vsp5" | grep -oE '/static/js/vsp_data_source_charts_v1\.js[^"]*' | head -n 3
