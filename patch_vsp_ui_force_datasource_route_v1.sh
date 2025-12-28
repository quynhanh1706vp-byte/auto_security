#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

echo "[PATCH] Force add /api/vsp/datasource_v2 proxy vào vsp_demo_app.py (8910 -> core 8961)"

python - << 'PY'
from pathlib import Path

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

if "VSP_PROXY_DATASOURCE_V2_FORCE" in txt:
    print("[SKIP] Đã có VSP_PROXY_DATASOURCE_V2_FORCE trong", app_path)
else:
    block = """
# [VSP_PROXY_DATASOURCE_V2_FORCE] Simple proxy /api/vsp/datasource_v2 -> core 8961
import requests, urllib.parse
from flask import request, Response

@app.route("/api/vsp/datasource_v2", methods=["GET"])
def vsp_proxy_datasource_v2_force():
    try:
        qs = urllib.parse.urlencode(request.args)
        core_url = "http://localhost:8961/api/vsp/datasource_v2"
        if qs:
            core_url = core_url + "?" + qs
        r = requests.get(core_url, timeout=60)
        resp = Response(r.content, status=r.status_code)
        ct = r.headers.get("Content-Type") or "application/json"
        resp.headers["Content-Type"] = ct
        return resp
    except Exception as e:
        return {"ok": False, "error": f"proxy datasource_v2 error: {e}"}, 500
"""

    app_path.write_text(txt.rstrip() + block + "\n", encoding="utf-8")
    print("[OK] Appended VSP_PROXY_DATASOURCE_V2_FORCE vào", app_path)
PY

echo "[PATCH] Done."
