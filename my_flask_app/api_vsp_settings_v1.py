from __future__ import annotations

from flask import Blueprint, jsonify, request, current_app
from pathlib import Path
import json

bp_vsp_settings_v1 = Blueprint("vsp_settings_v1", __name__)

# ROOT = /home/test/Data/SECURITY_BUNDLE
ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = ROOT / "config" / "vsp_settings.json"

DEFAULT_CONFIG = {
    "profile": "EXT+",
    "root": str(ROOT),
    "run_dir_base": str(ROOT / "out"),
    # cấu hình nguồn scan: code / url
    "scan": {
        "mode": "code",  # code | url
        "code_src": "/home/test/Data/khach6",
        "url_target": "https://staging-zt.lab.linksafe.vn",
        # tuỳ chọn cho ANY-URL / login engine phía sau
        "url_login_profile": "itim_local",
    },
    "tools": {
        "gitleaks": True,
        "semgrep": True,
        "bandit": True,
        "trivy_fs": True,
        "syft": True,
        "grype": True,
        "kics": True,
        "codeql": True,
    },
}


def _merge_scan(base_scan: dict, override_scan: dict) -> dict:
    scan = dict(base_scan or {})
    for k, v in (override_scan or {}).items():
        if k in ("mode", "code_src", "url_target", "url_login_profile"):
            scan[k] = v
    # đảm bảo mode hợp lệ
    if scan.get("mode") not in ("code", "url"):
        scan["mode"] = "code"
    return scan


def _deep_merge_config(base: dict, override: dict) -> dict:
    cfg = dict(base)

    for k, v in (override or {}).items():
        if k == "tools" and isinstance(v, dict):
            tools = dict(base.get("tools", {}))
            for tk, tv in v.items():
                if tk in tools:
                    tools[tk] = bool(tv)
            cfg["tools"] = tools
        elif k == "scan" and isinstance(v, dict):
            scan_base = base.get("scan", DEFAULT_CONFIG["scan"])
            cfg["scan"] = _merge_scan(scan_base, v)
        else:
            cfg[k] = v

    return cfg


def load_config() -> dict:
    try:
        if not CONFIG_PATH.is_file():
            return dict(DEFAULT_CONFIG)
        with CONFIG_PATH.open("r", encoding="utf-8") as f:
            raw = json.load(f) or {}
        return _deep_merge_config(DEFAULT_CONFIG, raw)
    except Exception as e:  # pragma: no cover
        current_app.logger.warning("[VSP][SETTINGS] load_config error: %r", e)
        return dict(DEFAULT_CONFIG)


def save_config(update: dict) -> dict:
    cfg = load_config()

    allowed_keys = {"profile", "root", "run_dir_base", "tools", "scan"}
    cleaned = {k: v for k, v in (update or {}).items() if k in allowed_keys}
    cfg = _deep_merge_config(cfg, cleaned)

    try:
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with CONFIG_PATH.open("w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
    except Exception as e:  # pragma: no cover
        current_app.logger.exception("[VSP][SETTINGS] save_config error: %r", e)
        raise
    return cfg


@bp_vsp_settings_v1.route("/api/vsp/settings/get")
def api_settings_get():
    cfg = load_config()
    return jsonify(
        {
            "ok": True,
            "profile": cfg.get("profile"),
            "root": cfg.get("root"),
            "run_dir_base": cfg.get("run_dir_base"),
            "scan": cfg.get("scan", {}),
            "tools": cfg.get("tools", {}),
        }
    )


@bp_vsp_settings_v1.route("/api/vsp/settings/update", methods=["POST"])
def api_settings_update():
    try:
        payload = request.get_json(force=True, silent=False) or {}
    except Exception as e:
        return (
            jsonify({"ok": False, "error": "bad_json", "detail": str(e)}),
            400,
        )

    try:
        cfg = save_config(payload)
        current_app.logger.info("[VSP][SETTINGS] updated: %s", cfg)
        return jsonify({"ok": True, "settings": cfg})
    except Exception as e:
        current_app.logger.exception("[VSP][SETTINGS] save failed: %r", e)
        return jsonify({"ok": False, "error": "save_failed"}), 500
