#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

echo "[PATCH] Fix indent cho block VSP_UI_DATASOURCE_FORCE_V3 trong $APP"

python - << 'PY'
from pathlib import Path

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

marker = "# === VSP_UI_DATASOURCE_FORCE_V3"
idx = txt.find(marker)

if idx == -1:
    print("[WARN] Không tìm thấy marker VSP_UI_DATASOURCE_FORCE_V3 – chưa từng chèn block?")
    raise SystemExit(0)

prefix = txt[:idx].rstrip() + "\n\n"

block = r"""
# === VSP_UI_DATASOURCE_FORCE_V3 – proxy /api/vsp/datasource_v2 (UI 8910 -> core 8961) ===
from flask import request, Response  # safe nếu đã import trước
import requests, urllib.parse

@app.route("/api/vsp/datasource_v2", methods=["GET"])
def vsp_ui_datasource_v2():
    # Lấy toàn bộ query string & forward sang core
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

new_txt = prefix + block.strip() + "\n"
app_path.write_text(new_txt, encoding="utf-8")
print("[OK] Đã ghi lại", app_path)
PY

echo "[PATCH] Done."
