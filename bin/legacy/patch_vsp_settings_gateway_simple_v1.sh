#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

echo "[PATCH] Thêm route /api/vsp/settings_v1 (gateway đơn giản, lưu file JSON)."

python - << 'PY'
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8")

marker = "VSP_SETTINGS_GATEWAY_SIMPLE_v1"
if marker in txt:
    print("[INFO] Route settings_v1 đã tồn tại, bỏ qua.")
else:
    block = f"""
# {marker}
import json
from pathlib import Path as _Path
from flask import request, jsonify

_VSP_ROOT = _Path("/home/test/Data/SECURITY_BUNDLE").resolve()
_SETTINGS_FILE = _VSP_ROOT / "out" / "vsp_settings_v1.json"

def _load_settings_from_file():
    if _SETTINGS_FILE.is_file():
        try:
            return json.loads(_SETTINGS_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    # default settings nếu chưa có file
    return {{
        "profile_default": "FULL_EXT",
        "severity_gate_min": "MEDIUM",
        "tools_enabled": {{
            "semgrep": True,
            "gitleaks": True,
            "bandit": True,
            "trivy_fs": True,
            "grype": True,
            "syft": True,
            "kics": True,
            "codeql": False
        }},
        "general": {{
            "default_src_root": "/home/test/Data/khach6",
            "default_run_dir": "out/RUN_YYYYmmdd_HHMMSS",
            "default_export_type": "HTML+CSV",
            "ui_table_max_rows": 5000
        }},
        "integrations": {{
            "webhook_url": "",
            "slack_channel": "",
            "dependency_track_url": ""
        }}
    }}

@app.route("/api/vsp/settings_v1", methods=["GET", "POST"])
def vsp_settings_v1():
    \"\"\"GET/POST settings trực tiếp trên gateway 8910 (lưu file JSON).\"\"\"
    if request.method == "GET":
        settings = _load_settings_from_file()
        return jsonify(ok=True, settings=settings)

    payload = request.get_json(silent=True) or {{}}
    try:
        _SETTINGS_FILE.parent.mkdir(parents=True, exist_ok=True)
        _SETTINGS_FILE.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    except Exception as e:
        return jsonify(ok=False, error=str(e)), 500
    return jsonify(ok=True)
"""

    key = 'if __name__ == "__main__":'
    if key in txt:
        txt = txt.replace(key, block + "\n\n" + key)
        print("[OK] Đã chèn block settings_v1 trước", key)
    else:
        txt = txt + "\\n\\n" + block
        print("[WARN] Không thấy if __name__ == '__main__', append block cuối file.")

    p.write_text(txt, encoding="utf-8")
PY

echo "[PATCH] DONE. Nhớ restart vsp_demo_app.py (gateway 8910)."
