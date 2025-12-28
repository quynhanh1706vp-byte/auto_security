#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

echo "[PATCH] Thêm route /api/vsp/settings_v1 vào vsp_demo_app.py (gateway 8910)"

python - << 'PY'
from pathlib import Path
import textwrap

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8")

marker = "VSP_SETTINGS_GATEWAY_v1"
if marker in txt:
    print("[INFO] Route gateway settings đã tồn tại, bỏ qua.")
else:
    # chèn trước dòng cuối cùng nếu có 'if __name__ == "__main__"' cho gọn
    block = textwrap.dedent(f"""
    # {marker}
    import os, requests
    from flask import request, jsonify

    _CORE_BASE = os.environ.get("VSP_CORE_BASE", "http://127.0.0.1:8961")

    @app.route("/api/vsp/settings_v1", methods=["GET", "POST"])
    def vsp_settings_v1_gateway():
        \"\"\"Gateway proxy /api/vsp/settings_v1 -> core {_CORE_BASE}/api/vsp/settings_v1\"\"\"
        url = _CORE_BASE + "/api/vsp/settings_v1"
        try:
            if request.method == "GET":
                r = requests.get(url, timeout=10)
            else:
                payload = request.get_json(silent=True) or {{}}
                r = requests.post(url, json=payload, timeout=10)
            # Trả nguyên JSON/text từ core
            headers = {{"Content-Type": r.headers.get("Content-Type", "application/json")}}
            return r.text, r.status_code, headers
        except Exception as e:
            return jsonify(ok=False, error=f"gateway_settings_error: {{e}}"), 500
    """)

    if "if __name__ == \"__main__\":" in txt:
        txt = txt.replace("if __name__ == \"__main__\":", block + "\n\nif __name__ == \"__main__\":")
    else:
        txt = txt + "\n\n" + block

    p.write_text(txt, encoding="utf-8")
    print("[OK] Đã append route gateway settings vào", p)
PY

echo "[PATCH] DONE. Hãy restart vsp_demo_app.py (gateway 8910)."
