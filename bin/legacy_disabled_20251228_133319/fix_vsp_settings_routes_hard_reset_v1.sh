#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

if [[ ! -f "$APP" ]]; then
  echo "[ERR] Không tìm thấy $APP" >&2
  exit 1
fi

BACKUP="${APP}.bak_settings_hardreset_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BACKUP"
echo "[HARDRESET] Backup: $BACKUP"

python - << 'PY'
from pathlib import Path

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

print("[HARDRESET] Kích thước file trước khi xử lý:", len(txt))

# 1) Gỡ toàn bộ các block cũ theo marker
marker_pairs = [
    ("# === VSP_SETTINGS_INLINE_V1_BEGIN ===", "# === VSP_SETTINGS_INLINE_V1_END ==="),
    ("# === VSP_SETTINGS_INLINE_SIMPLE_V1 ===", "# === /VSP_SETTINGS_INLINE_SIMPLE_V1 ==="),
    ("# === VSP_SETTINGS_INLINE_SIMPLE_V2 ===", "# === /VSP_SETTINGS_INLINE_SIMPLE_V2 ==="),
    ("# === VSP_SETTINGS_ROUTES_FINAL ===", "# === /VSP_SETTINGS_ROUTES_FINAL ==="),
]

for start, end in marker_pairs:
    while start in txt:
        s = txt.find(start)
        e = txt.find(end, s)
        if e == -1:
            # Không tìm thấy end marker → chỉ cắt dòng start
            print(f"[HARDRESET] Tìm thấy {start} nhưng không thấy end, cắt 1 dòng.")
            line_end = txt.find("\n", s)
            if line_end == -1:
                txt = txt[:s]
            else:
                txt = txt[:s] + txt[line_end+1:]
            break
        e += len(end)
        print(f"[HARDRESET] Remove block {start} .. {end}")
        txt = txt[:s] + "\n" + txt[e:]

# 2) Nếu vẫn còn def vsp_settings_v1 / vsp_rule_overrides_v1 thì xóa thêm bằng regex thô
import re

pattern_funcs = [
    r"@app\.route\(\"/api/vsp/settings_v1\"[\s\S]+?^#",
    r"@app\.route\(\"/api/vsp/rule_overrides_v1\"[\s\S]+?^#",
]

orig_txt = txt
for pat in pattern_funcs:
    new_txt, n = re.subn(pat, "# [HARDRESET] removed legacy settings/rules block\n#", txt, flags=re.MULTILINE)
    if n:
        print(f"[HARDRESET] Regex removed {n} block(s) for pattern: {pat}")
    txt = new_txt

# 3) Cuối cùng, append block canonical mới với endpoint khác tên
block = r"""

# === VSP_SETTINGS_ROUTES_CANONICAL_V1 ===
from pathlib import Path as _VSPPathSettings
import json as _vspJsonSettings

_SETTINGS_ROOT_CANON = _VSPPathSettings(__file__).resolve().parents[1]
_SETTINGS_CFG_DIR_CANON = _SETTINGS_ROOT_CANON / "config"


def _settings_load_json_canon(path, default):
    if path.is_file():
        try:
            return _vspJsonSettings.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return default
    return default


@app.route(
    "/api/vsp/settings_v1",
    methods=["GET", "POST"],
    endpoint="vsp_settings_v1_api",
)
def vsp_settings_v1_api():
    from flask import request, jsonify

    cfg_path = _SETTINGS_CFG_DIR_CANON / "vsp_settings_v1.json"

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
                "codeql": True,
            },
        }
        data = _settings_load_json_canon(cfg_path, default)
        return jsonify(ok=True, settings=data)

    payload = request.get_json(silent=True) or {}
    settings = payload.get("settings")
    if not isinstance(settings, dict):
        return jsonify(ok=False, error="settings must be an object"), 400

    _SETTINGS_CFG_DIR_CANON.mkdir(parents=True, exist_ok=True)
    cfg_path.write_text(
        _vspJsonSettings.dumps(settings, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return jsonify(ok=True)


@app.route(
    "/api/vsp/rule_overrides_v1",
    methods=["GET", "POST"],
    endpoint="vsp_rule_overrides_v1_api",
)
def vsp_rule_overrides_v1_api():
    from flask import request, jsonify

    cfg_path = _SETTINGS_CFG_DIR_CANON / "vsp_rule_overrides_v1.json"

    if request.method == "GET":
        default = []
        items = _settings_load_json_canon(cfg_path, default)
        return jsonify(ok=True, items=items)

    payload = request.get_json(silent=True) or {}
    items = payload.get("items", [])
    if not isinstance(items, list):
        return jsonify(ok=False, error="items must be a list"), 400

    _SETTINGS_CFG_DIR_CANON.mkdir(parents=True, exist_ok=True)
    cfg_path.write_text(
        _vspJsonSettings.dumps(items, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return jsonify(ok=True)
# === /VSP_SETTINGS_ROUTES_CANONICAL_V1 ===
"""

txt = txt + block + "\n"
app_path.write_text(txt, encoding="utf-8")
print("[HARDRESET] Kích thước file sau khi xử lý:", len(txt))
PY

echo "[HARDRESET] Done."
