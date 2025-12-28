#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_canon_v_${TS}"
echo "[BACKUP] ${W}.bak_canon_v_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_CANONICALIZE_STATIC_ASSET_V_V1"
if marker in s:
    print("[OK] marker already present; skip")
    sys.exit(0)

# append safe block at end (no indentation assumptions)
block = r'''
# --- VSP_P2_CANONICALIZE_STATIC_ASSET_V_V1 ---
try:
    import os as _os
    from flask import request as _request, redirect as _redirect
    from urllib.parse import urlencode as _urlencode

    @app.before_request
    def _vsp_canonicalize_static_v():
        try:
            path = _request.path or ""
            if not path.startswith("/static/"):
                return None
            # only normalize js/css (avoid images/fonts if you want)
            if not (path.endswith(".js") or path.endswith(".css")):
                return None

            pinned = _os.environ.get("VSP_ASSET_V") or _os.environ.get("VSP_RELEASE_TS")
            if not pinned:
                return None

            q = _request.args.to_dict(flat=True)
            cur = q.get("v")
            if cur == pinned:
                return None

            q["v"] = pinned
            # keep other query params if any
            new_url = path + "?" + _urlencode(q)
            return _redirect(new_url, code=302)
        except Exception:
            return None
# --- end VSP_P2_CANONICALIZE_STATIC_ASSET_V_V1 ---
except Exception:
    pass
'''
p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended canonicalizer block")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK: $W"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }
else
  echo "[WARN] systemctl not found; restart manually"
fi

echo "== quick verify: static request with wrong v should redirect to pinned =="
PIN="$(sudo systemctl show "$SVC" -p Environment --no-pager | tr ' ' '\n' | sed -n 's/^VSP_ASSET_V=//p' | head -n 1 || true)"
echo "[INFO] pinned VSP_ASSET_V=$PIN"

code="$(curl -sS -o /dev/null -w "%{http_code}" -I "$BASE/static/js/vsp_tabs4_autorid_v1.js?v=123")"
loc="$(curl -sS -I "$BASE/static/js/vsp_tabs4_autorid_v1.js?v=123" | awk -F': ' 'tolower($1)=="location"{print $2}' | tr -d '\r' | tail -n 1)"
echo "HTTP=$code"
echo "Location=$loc"

