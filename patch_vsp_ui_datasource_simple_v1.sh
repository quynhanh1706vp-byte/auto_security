#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

echo "[PATCH] Append route /api/vsp/datasource_v2 đơn giản vào $APP"

python - << 'PY'
from pathlib import Path

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

if "/api/vsp/datasource_v2" in txt:
    print("[SKIP] Đã có /api/vsp/datasource_v2 trong vsp_demo_app.py – bỏ qua")
else:
    block = """

# === VSP_UI_DATASOURCE_SIMPLE_V1 – proxy /api/vsp/datasource_v2 (UI 8910 -> core 8961) ===
from flask import request, Response  # import lại cũng không sao
import requests, urllib.parse

@app.route("/api/vsp/datasource_v2", methods=["GET"])
def vsp_ui_datasource_v2_simple():
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
    print("[OK] Đã append route /api/vsp/datasource_v2 vào", app_path)
PY

echo "[PATCH] Done."
