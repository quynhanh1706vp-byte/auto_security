#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$UI_ROOT/vsp_demo_app.py"

if [[ ! -f "$TARGET" ]]; then
  echo "[ERR] Không tìm thấy $TARGET"
  exit 1
fi

BACKUP="${TARGET}.bak_settings_ui_endpoint_$(date +%Y%m%d_%H%M%S)"
cp "$TARGET" "$BACKUP"
echo "[BACKUP] $TARGET -> $BACKUP"

export VSP_DEMO_APP="$TARGET"

python - << 'PY'
import os, pathlib, textwrap

target = pathlib.Path(os.environ["VSP_DEMO_APP"])
txt = target.read_text(encoding="utf-8")

# Nếu route mới đã tồn tại thì bỏ qua
if "/api/vsp/settings_ui_v1" in txt:
    print("[INFO] /api/vsp/settings_ui_v1 đã tồn tại, bỏ qua patch.")
    raise SystemExit(0)

marker = "def _save_settings_to_file("
idx = txt.find(marker)
if idx == -1:
    raise SystemExit("Không thấy helpers _save_settings_to_file – hãy chạy patch helpers trước.")

# Tìm hết thân hàm _save_settings_to_file để chèn phía sau
end_idx = txt.find("\ndef ", idx + 1)
if end_idx == -1:
    # không có hàm nào sau nữa -> chèn trước if __main__
    end_idx = txt.find("if __name__ == \"__main__\"")
    if end_idx == -1:
        end_idx = len(txt)

before = txt[:end_idx]
after = txt[end_idx:]

block = textwrap.dedent('''
    @app.route("/api/vsp/settings_ui_v1", methods=["GET", "POST"])
    def vsp_settings_ui_v1():
        """
        Settings API cho UI:
        - GET  -> trả JSON {ok: true, settings: {...}}
        - POST -> nhận {settings: {...}} hoặc object raw, lưu file rồi trả lại JSON.
        """
        from flask import request, jsonify

        if request.method == "GET":
            settings = _load_settings_from_file()
            return jsonify({"ok": True, "settings": settings})

        payload = request.get_json(silent=True) or {}
        # Nếu payload dạng {settings: {...}} thì lấy bên trong, còn không thì dùng cả object
        if isinstance(payload, dict) and "settings" in payload and isinstance(payload["settings"], dict):
            settings = payload["settings"]
        else:
            settings = payload

        _save_settings_to_file(settings)
        return jsonify({"ok": True, "settings": settings})
''').lstrip("\n")

new_txt = before.rstrip() + "\n\n" + block + "\n\n" + after.lstrip()
target.write_text(new_txt, encoding="utf-8")
print("[PATCH] Đã thêm route /api/vsp/settings_ui_v1 (vsp_settings_ui_v1).")
PY

echo "[OK] Done patch_vsp_settings_ui_endpoint_v1."
