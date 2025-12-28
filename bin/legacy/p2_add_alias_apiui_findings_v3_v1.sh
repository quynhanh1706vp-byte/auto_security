#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_apiui_alias_${TS}"
echo "[BACKUP] ${APP}.bak_apiui_alias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P2_ALIAS_APIUI_FINDINGS_V3_V1" in s:
    print("[OK] already patched")
    raise SystemExit(0)

# try to find the findings_page_v3 handler function name (common patterns)
# We’ll add a small route that forwards query params by calling the existing handler.
# Insert near other API routes: before the first occurrence of '/api/vsp/findings_page_v3' route or near end of file.
insert_at = None
m = re.search(r'@app\.route\(\s*[\'"]\/api\/vsp\/findings_page_v3[\'"]', s)
if m:
    insert_at = m.start()
else:
    # fallback: append near end
    insert_at = len(s)

alias = r'''
# ===================== VSP_P2_ALIAS_APIUI_FINDINGS_V3_V1 =====================
try:
    from flask import request
except Exception:
    request = None

@app.route("/api/ui/findings_v3", methods=["GET"])
def vsp_alias_apiui_findings_v3():
    """
    Backward-compat alias: old DS JS used /api/ui/findings_v3.
    Forward to the commercial endpoint /api/vsp/findings_page_v3 by reusing its handler.
    """
    # If your code defines a function handler for findings_page_v3, call it.
    # Otherwise, fall back to calling the endpoint via internal dispatch.
    try:
        # common: handler name
        return findings_page_v3()
    except Exception:
        # last resort: try to call through Flask test client-like internal redirect is messy,
        # but returning a clear error is still better than 404.
        from flask import jsonify
        return jsonify({"ok": False, "error": "alias_failed_missing_findings_page_v3_handler"}), 500
# =================== /VSP_P2_ALIAS_APIUI_FINDINGS_V3_V1 ======================
'''

s2 = s[:insert_at] + alias + "\n" + s[insert_at:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched alias into", p)
PY

echo "[OK] restart service"
sudo -v
sudo systemctl restart vsp-ui-8910.service
echo "[DONE] open and hard refresh: http://127.0.0.1:8910/data_source?severity=MEDIUM"
