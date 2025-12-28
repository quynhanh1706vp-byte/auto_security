#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_rellatest_urls_${TS}"
echo "[BACKUP] ${APP}.bak_rellatest_urls_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RELEASE_LATEST_ADD_URLS_IN_APP_V1"
if marker in s:
    print("[OK] already present:", marker)
else:
    # find release_latest handler (best-effort)
    # We will wrap jsonify payload just before return in that handler if it exists;
    # otherwise append a tiny AFTER_REQUEST hook to enrich only /api/vsp/release_latest responses.
    if re.search(r'@app\.(get|route)\(["\']\/api\/vsp\/release_latest["\']', s):
        print("[INFO] found explicit /api/vsp/release_latest handler; will install after_request enricher anyway (safer).")

    block = textwrap.dedent(r'''
    # ===================== VSP_P1_RELEASE_LATEST_ADD_URLS_IN_APP_V1 =====================
    try:
        from urllib.parse import quote as _vsp_quote
    except Exception:
        _vsp_quote = None

    @app.after_request
    def _vsp_p1_release_latest_add_urls_in_app_v1(resp):
        """
        Enrich /api/vsp/release_latest JSON with:
          - package_url: /out_ci/releases/<name>.tgz (compat link; now 302->download)
          - download_url: /api/vsp/release_pkg_download?path=<release_pkg>
        This avoids touching WSGI gateway intercept logic.
        """
        try:
            if not resp:
                return resp
            # match path (Flask request is available)
            from flask import request
            if request.path != "/api/vsp/release_latest":
                return resp
            ct = (resp.headers.get("Content-Type") or "").lower()
            if "application/json" not in ct:
                return resp

            import json
            data = json.loads(resp.get_data(as_text=True) or "{}")
            if not isinstance(data, dict) or not data.get("ok"):
                return resp

            rel = data.get("release_pkg") or ""
            if rel and isinstance(rel, str):
                name = rel.split("/")[-1]
                # compat URL (browser paste)
                data["package_url"] = f"/out_ci/releases/{name}"
                # canonical download URL
                if _vsp_quote:
                    q = _vsp_quote(rel, safe="")
                else:
                    q = rel.replace(" ", "%20")
                data["download_url"] = f"/api/vsp/release_pkg_download?path={q}"

            # re-encode response (keep status/headers)
            resp.set_data(json.dumps(data, ensure_ascii=False))
            resp.headers["Content-Length"] = str(len(resp.get_data()))
            resp.headers["X-VSP-REL-URLS"] = "ok"
            return resp
        except Exception:
            return resp
    # ===================== /VSP_P1_RELEASE_LATEST_ADD_URLS_IN_APP_V1 =====================
    ''').strip() + "\n"

    p.write_text(s.rstrip() + "\n\n" + block, encoding="utf-8")
    print("[OK] appended", marker)

PY

echo "== compile check =="
python3 -m py_compile "$APP"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify JSON has urls =="
curl -fsS "$BASE/api/vsp/release_latest" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=",j.get("ok"))
print("package_url=",j.get("package_url"))
print("download_url=",j.get("download_url"))
PY

echo "[DONE] release_latest now includes package_url + download_url."
