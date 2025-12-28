#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_FILE="$UI_ROOT/vsp_demo_app.py"

if [ ! -f "$APP_FILE" ]; then
  echo "[ERR] Không tìm thấy $APP_FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$APP_FILE" "${APP_FILE}.bak_rule_api_${TS}"
echo "[BACKUP] $APP_FILE -> ${APP_FILE}.bak_rule_api_${TS}"

python3 - << 'PY'
from pathlib import Path

app_path = Path("vsp_demo_app.py")
text = app_path.read_text(encoding="utf-8")

if "/api/vsp/rule_overrides_v1" in text:
    print("[INFO] Đã có /api/vsp/rule_overrides_v1 trong vsp_demo_app.py, bỏ qua patch.")
else:
    block = r"""

# === VSP Rule Overrides API stub V1 ===
from pathlib import Path as _VSP_Path
import json as _vsp_json

@app.route("/api/vsp/rule_overrides_v1", methods=["GET", "POST"])
def vsp_rule_overrides_v1_api():
    \"""
    Simple file-based storage cho rule_overrides_v1.
    File lưu tại: ../config/rule_overrides_v1.json (tính từ thư mục ui/).
    \"""
    root = _VSP_Path(__file__).resolve().parent.parent  # .../SECURITY_BUNDLE
    cfg_dir = root / "config"
    cfg_dir.mkdir(exist_ok=True)
    cfg_file = cfg_dir / "rule_overrides_v1.json"

    if request.method == "GET":
        if cfg_file.exists():
            try:
                data = _vsp_json.loads(cfg_file.read_text(encoding="utf-8"))
            except Exception as exc:  # pragma: no cover
                app.logger.warning("Invalid rule_overrides_v1.json: %s", exc)
                data = []
        else:
            data = []
        return jsonify(data)

    # POST: nhận list hoặc object có items
    payload = request.get_json(force=True, silent=True)
    if payload is None:
        payload = []

    # Chấp nhận cả dạng list lẫn {"items": [...]}
    to_save = payload
    try:
        cfg_file.write_text(
            _vsp_json.dumps(to_save, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
    except Exception as exc:  # pragma: no cover
        app.logger.error("Cannot write rule_overrides_v1.json: %s", exc)
        return jsonify({"ok": False, "error": str(exc)}), 500

    return jsonify(to_save)
"""
    # chèn block trước dòng cuối cùng (thường là if __name__ == "__main__")
    marker = "if __name__ == \"__main__\""
    idx = text.find(marker)
    if idx == -1:
        text = text + block
        print("[WARN] Không tìm thấy if __name__ == '__main__', append block vào cuối file.")
    else:
        text = text[:idx] + block + "\n" + text[idx:]
        print("[OK] Đã chèn block Rule Overrides API stub trước main.")

    app_path.write_text(text, encoding="utf-8")
PY
