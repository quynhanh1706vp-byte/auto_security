#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$UI_ROOT/vsp_demo_app.py"

if [[ ! -f "$TARGET" ]]; then
  echo "[ERR] Không tìm thấy $TARGET"
  exit 1
fi

BACKUP="${TARGET}.bak_settings_view_reset_$(date +%Y%m%d_%H%M%S)"
cp "$TARGET" "$BACKUP"
echo "[BACKUP] $TARGET -> $BACKUP"

export VSP_DEMO_APP="$TARGET"

python - << 'PY'
import os, pathlib

target = pathlib.Path(os.environ["VSP_DEMO_APP"])
txt = target.read_text(encoding="utf-8")

lines = txt.splitlines()
clean_lines = []

i = 0
removed = 0

while i < len(lines):
    line = lines[i]
    stripped = line.lstrip()

    # Bỏ block bắt đầu từ @app.route("/api/vsp/settings_v1", ...)
    if '@app.route("/api/vsp/settings_v1"' in line or "@app.route('/api/vsp/settings_v1'" in line:
        removed += 1
        i += 1
        # skip cho tới decorator khác hoặc if __main__
        while i < len(lines):
            s = lines[i].lstrip()
            if s.startswith('@app.route(') or s.startswith('if __name__ == "__main__":'):
                break
            i += 1
        continue

    # Nếu còn def vsp_settings_v1(...) lẻ loi thì xoá luôn
    if stripped.startswith('def vsp_settings_v1('):
        removed += 1
        i += 1
        while i < len(lines):
            s = lines[i].lstrip()
            if s.startswith('@app.route(') or s.startswith('if __name__ == "__main__":'):
                break
            i += 1
        continue

    clean_lines.append(line)
    i += 1

print(f"[INFO] Removed {removed} old vsp_settings_v1 block(s)")

cleaned_txt = "\n".join(clean_lines) + "\n"

marker = 'def _save_settings_to_file('
idx = cleaned_txt.find(marker)
if idx == -1:
    raise SystemExit("Không thấy helpers _save_settings_to_file – patch helpers phải chạy trước.")

# Chèn view mới ngay SAU helpers
after_helpers_idx = cleaned_txt.find("\n", idx)
if after_helpers_idx == -1:
    after_helpers_idx = len(cleaned_txt)

before = cleaned_txt[: after_helpers_idx + 1]
after = cleaned_txt[after_helpers_idx + 1 :]

block = '''
@app.route("/api/vsp/settings_v1", methods=["GET", "POST"])
def vsp_settings_v1():
    """
    Settings API:
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
'''.lstrip("\\n")

new_txt = before.rstrip() + "\\n\\n" + block + "\\n\\n" + after.lstrip()
target.write_text(new_txt, encoding="utf-8")
print("[PATCH] Đã reset view vsp_settings_v1 (JSON GET/POST).")
PY

echo "[OK] Done patch vsp_settings_view_reset_v1."
