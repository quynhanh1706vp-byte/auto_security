#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

echo "[PATCH] Force add /api/vsp/datasource_v2 proxy v3 vào $APP"

python - << 'PY'
from pathlib import Path

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

# Nếu đã có /api/vsp/datasource_v2 thì thôi
if "/api/vsp/datasource_v2" in txt:
    print("[SKIP] Đã có route /api/vsp/datasource_v2 – bỏ qua")
else:
    # Bổ sung import request, Response nếu thiếu
    if "from flask import" in txt and "request" not in txt:
        txt = txt.replace("from flask import ", "from flask import request, Response, ")
        print("[OK] Bổ sung request, Response vào import flask")

    block = """

# [VSP_PROXY_DATASOURCE_V2_FORCE_V3] proxy 8910 -> core 8961
import requests, urllib.parse

@app.route("/api/vsp/datasource_v2", methods=["GET"])
def vsp_proxy_datasource_v2_force_v3():
    qs = urllib.parse.urlencode(dict(request.args))
    core_url = "http://localhost:8961/api/vsp/datasource_v2"
    if qs:
        core_url = f"{core_url}?{qs}"
    try:
        r = requests.get(core_url, timeout=60)
        resp = Response(r.content, status=r.status_code)
        resp.headers["Content-Type"] = r.headers.get("Content-Type", "application/json")
        return resp
    except Exception as exc:
        return {"ok": False, "error": f"proxy datasource_v2 error: {exc}"}, 500
"""
    app_path.write_text(txt.rstrip() + block + "\n", encoding="utf-8")
    print("[OK] Appended new proxy route vào", app_path)
PY

echo "[PATCH] Done."
