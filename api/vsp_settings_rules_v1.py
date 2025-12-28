from flask import Blueprint, jsonify, request
from pathlib import Path
import json

bp_settings_rules = Blueprint("bp_settings_rules", __name__)

# ROOT = /home/test/Data/SECURITY_BUNDLE
ROOT = Path(__file__).resolve().parents[2]
CONFIG_DIR = ROOT / "config"


def load_json(path, default):
    if path.is_file():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return default
    return default


@bp_settings_rules.route("/api/vsp/settings_v1", methods=["GET", "POST"])
def settings_v1():
    """
    GET  -> trả về config Settings hiện tại
    POST -> cập nhật config Settings
    """
    cfg_path = CONFIG_DIR / "vsp_settings_v1.json"

    if request.method == "GET":
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
                "codeql": True
            }
        }
        data = load_json(cfg_path, default)
        return jsonify(ok=True, settings=data)

    payload = request.get_json(silent=True) or {}
    settings = payload.get("settings")
    if not isinstance(settings, dict):
        return jsonify(ok=False, error="settings must be an object"), 400

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    cfg_path.write_text(json.dumps(settings, indent=2, ensure_ascii=False), encoding="utf-8")
    return jsonify(ok=True)


@bp_settings_rules.route("/api/vsp/rule_overrides_v1", methods=["GET", "POST"])
def rule_overrides_v1():
    """
    GET  -> list rule overrides
    POST -> ghi lại toàn bộ list overrides
    """
    cfg_path = CONFIG_DIR / "vsp_rule_overrides_v1.json"

    if request.method == "GET":
        default = []
        items = load_json(cfg_path, default)
        return jsonify(ok=True, items=items)

    payload = request.get_json(silent=True) or {}
    items = payload.get("items", [])
    if not isinstance(items, list):
        return jsonify(ok=False, error="items must be a list"), 400

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    cfg_path.write_text(json.dumps(items, indent=2, ensure_ascii=False), encoding="utf-8")
    return jsonify(ok=True)
