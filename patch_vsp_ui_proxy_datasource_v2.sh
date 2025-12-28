#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/vsp_demo_app.py"

echo "[PATCH] Add proxy /api/vsp/datasource_v2 vào vsp_demo_app.py (8910 -> core 8961)"

python - << 'PY'
from pathlib import Path
import re

root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
app_path = root / "vsp_demo_app.py"
txt = app_path.read_text(encoding="utf-8")

if "VSP_PROXY_DATASOURCE_V2" in txt:
    print("[SKIP] Đã có proxy datasource_v2 trong vsp_demo_app.py")
else:
    # Đảm bảo có import requests
    if "import requests" not in txt:
        if "from flask import" in txt:
            txt = txt.replace("from flask import",
                              "import requests\nfrom flask import",
                              1)
        else:
            # fallback: thêm import requests ở đầu file
            txt = "import requests\n" + txt

    block = r"""
# [VSP_PROXY_DATASOURCE_V2] Proxy /api/vsp/datasource_v2 -> core API trên 8961
import urllib.parse

CORE_BASE_DATASRC = "http://localhost:8961"

@app.route("/api/vsp/datasource_v2", methods=["GET"])
def vsp_proxy_datasource_v2():
    from flask import request, Response
    try:
        qs = urllib.parse.urlencode(request.args)
        url = f"{CORE_BASE_DATASRC}/api/vsp/datasource_v2"
        if qs:
            url = url + "?" + qs
        r = requests.get(url, timeout=60)
        resp = Response(r.content, status=r.status_code)
        ct = r.headers.get("Content-Type")
        if ct:
            resp.headers["Content-Type"] = ct
        return resp
    except Exception as e:
        return {"ok": False, "error": f"proxy datasource_v2 error: {e}"}, 500
"""
    txt = txt.rstrip() + "\\n\\n" + block + "\\n"
    app_path.write_text(txt, encoding="utf-8")
    print("[OK] Đã append proxy datasource_v2 vào", app_path)
PY

echo "[PATCH] Done."
