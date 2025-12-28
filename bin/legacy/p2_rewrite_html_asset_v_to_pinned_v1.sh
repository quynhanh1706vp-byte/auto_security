#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need sort

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_html_assetv_rewrite_${TS}"
echo "[BACKUP] ${W}.bak_html_assetv_rewrite_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_AFTER_REQUEST_REWRITE_HTML_ASSETV_V1"

if marker in s:
    print("[OK] marker already present; skip")
    sys.exit(0)

block = r'''
# --- VSP_P2_AFTER_REQUEST_REWRITE_HTML_ASSETV_V1 ---
try:
    import os as _os, re as _re
    @app.after_request
    def _vsp_rewrite_html_asset_v(resp):
        try:
            ctype = (resp.headers.get("Content-Type") or "").lower()
            if "text/html" not in ctype:
                return resp

            pinned = _os.environ.get("VSP_ASSET_V") or _os.environ.get("VSP_RELEASE_TS")
            if not pinned:
                return resp

            data = resp.get_data()
            if not data:
                return resp
            try:
                txt = data.decode("utf-8", "replace")
            except Exception:
                return resp

            # Normalize any /static/*.js|css?v=ANYTHING -> v=pinned
            # Covers epoch v=176..., cut v=20251224, jinja leftovers, etc.
            pat = _re.compile(r'(/static/[^"\']+\.(?:js|css))\?v=[0-9A-Za-z_]+')
            new_txt = pat.sub(r'\1?v=' + pinned, txt)
            if new_txt != txt:
                resp.set_data(new_txt.encode("utf-8"))
                # Let Werkzeug/Flask recompute content-length if needed
                resp.headers.pop("Content-Length", None)
            return resp
        except Exception:
            return resp
# --- end VSP_P2_AFTER_REQUEST_REWRITE_HTML_ASSETV_V1 ---
except Exception:
    pass
'''
p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended after_request HTML asset_v rewriter")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK: $W"

echo "== restart service =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== quick verify: v values across tabs (should be 1) =="
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for pth in "${tabs[@]}"; do
  echo "-- $pth --"
  curl -sS "$BASE$pth" | grep -oE 'vsp_(bundle_tabs5|dashboard_luxe|tabs4_autorid|topbar_commercial)_v1\.js\?v=[0-9A-Za-z_]+' | sort -u || true
done
echo "== unique v =="
( for pth in "${tabs[@]}"; do curl -sS "$BASE$pth" | grep -oE 'v=[0-9A-Za-z_]+' || true; done ) \
 | sed 's/^v=//' | sort -u | sed 's/^/[V] /'
