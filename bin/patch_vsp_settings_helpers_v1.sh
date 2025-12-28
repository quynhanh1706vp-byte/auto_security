#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$UI_ROOT/vsp_demo_app.py"

if [[ ! -f "$TARGET" ]]; then
  echo "[ERR] Không tìm thấy $TARGET"
  exit 1
fi

BACKUP="${TARGET}.bak_settings_helpers_$(date +%Y%m%d_%H%M%S)"
cp "$TARGET" "$BACKUP"
echo "[BACKUP] $TARGET -> $BACKUP"

export VSP_DEMO_APP="$TARGET"

python - << 'PY'
import os, pathlib

target = pathlib.Path(os.environ["VSP_DEMO_APP"])
txt = target.read_text(encoding="utf-8")

if "_settings_file_path(" in txt:
    print("[INFO] Helpers đã tồn tại, bỏ qua.")
    raise SystemExit(0)

marker = "def vsp_settings_v1("
idx = txt.find(marker)
if idx == -1:
    raise SystemExit("Không tìm thấy def vsp_settings_v1(")

before = txt[:idx]
after = txt[idx:]

block = '''
def _settings_file_path():
    import os
    # Cho phép override bằng env nếu cần
    path = os.environ.get("VSP_SETTINGS_FILE")
    if path:
        return path
    return os.path.join(os.path.dirname(__file__), "config", "settings_v1.json")


def _load_settings_from_file():
    import json, os
    path = _settings_file_path()
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        # Nếu file hỏng thì trả rỗng để UI còn tự fill mặc định
        return {}


def _save_settings_to_file(data):
    import json, os
    path = _settings_file_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
'''

new_txt = before.rstrip() + "\\n\\n" + block + "\\n\\n" + after.lstrip()
target.write_text(new_txt, encoding="utf-8")
print("[PATCH] Đã thêm helpers _settings_file_path/_load_settings_from_file/_save_settings_to_file")
PY

echo "[OK] Xong patch helpers settings."
