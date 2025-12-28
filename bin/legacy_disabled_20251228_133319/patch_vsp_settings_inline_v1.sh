#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

if [[ ! -f "$APP" ]]; then
  echo "[ERR] Không tìm thấy $APP" >&2
  exit 1
fi

BACKUP="${APP}.bak_settings_inline_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BACKUP"
echo "[PATCH] Backup: $BACKUP"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = p.read_text(encoding="utf-8")

if "VSP_SETTINGS_INLINE_V1_BEGIN" in txt:
    print("[PATCH] Đã có block inline settings, không thêm nữa.")
else:
    block = r"""
# === VSP_SETTINGS_INLINE_V1_BEGIN ===
from pathlib import Path as _VSP_Path
import json as _vsp_json
from flask import request as _vsp_request, jsonify as _vsp_jsonify

# ROOT = /home/test/Data/SECURITY_BUNDLE
_VSP_ROOT = _VSP_Path(__file__).resolve().parents[1]
_VSP_CONFIG_DIR = _VSP_ROOT / "config"

def _vsp_load_json(path, default):
    if path.is_file():
        try:
            return _vsp_json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return default
    return default

@app.route("/api/vsp/settings_v1", methods=["GET", "POST"])
def vsp_settings_v1():
    """
    GET  -> trả về config Settings hiện tại
    POST -> ghi lại toàn bộ settings
    """
    cfg_path = _VSP_CONFIG_DIR / "vsp_settings_v1.json"

    if _vsp_request.method == "GET":
        default = {
            "profile_default": "FULL_EXT",
            "severity_gate": "MEDIUM",
            "tools": {
                "semgrep": True,
                "gitleaks": True,
                "bandit": True,
                "trivy_fs": True,
                "grype": True,
                "syft": True,
                "kics": True,
                "codeql": True,
            },
        }
        data = _vsp_load_json(cfg_path, default)
        return _vsp_jsonify(ok=True, settings=data)

    payload = _vsp_request.get_json(silent=True) or {}
    settings = payload.get("settings")
    if not isinstance(settings, dict):
        return _vsp_jsonify(ok=False, error="settings must be an object"), 400

    _VSP_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    cfg_path.write_text(
        _vsp_json.dumps(settings, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return _vsp_jsonify(ok=True)


@app.route("/api/vsp/rule_overrides_v1", methods=["GET", "POST"])
def vsp_rule_overrides_v1():
    """
    GET  -> list rule overrides
    POST -> ghi lại toàn bộ list overrides
    """
    cfg_path = _VSP_CONFIG_DIR / "vsp_rule_overrides_v1.json"

    if _vsp_request.method == "GET":
        default = []
        items = _vsp_load_json(cfg_path, default)
        return _vsp_jsonify(ok=True, items=items)

    payload = _vsp_request.get_json(silent=True) or {}
    items = payload.get("items", [])
    if not isinstance(items, list):
        return _vsp_jsonify(ok=False, error="items must be a list"), 400

    _VSP_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    cfg_path.write_text(
        _vsp_json.dumps(items, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return _vsp_jsonify(ok=True)
# === VSP_SETTINGS_INLINE_V1_END ===
"""
    txt = txt + "\n" + block + "\n"
    p.write_text(txt, encoding="utf-8")
    print("[PATCH] Đã thêm block inline settings vào vsp_demo_app.py")
PY

echo "[PATCH] Done."
