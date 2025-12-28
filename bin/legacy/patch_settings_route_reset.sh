#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/app.py"

echo "[i] ROOT = $ROOT"
cd "$ROOT"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP" >&2
  exit 1
fi

cp "$APP" "${APP}.bak_settings_route_reset_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py (settings route reset)."

python3 - << 'PY'
from pathlib import Path
import re

path = Path("app.py")
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

out = []
i = 0
n = len(lines)

while i < n:
    line = lines[i]
    s = line.replace("'", '"')

    # Bắt block @app.route("/settings") + def settings(...)
    if '@app.route("/settings"' in s:
        print(f"[INFO] Thấy @app.route('/settings') tại line {i+1}, sẽ thay toàn bộ block.")
        start = i

        # Đi tìm dòng def settings(...)
        j = i + 1
        while j < n and not re.match(r"\s*def\s+settings\s*\(", lines[j]):
            j += 1
        if j >= n:
            print("[WARN] Không tìm thấy def settings() sau decorator, bỏ qua patch.")
            out.append(line)
            i += 1
            continue

        def_line = j
        def_indent = len(lines[def_line]) - len(lines[def_line].lstrip(" "))
        print(f"[INFO] def settings() tại line {def_line+1}, indent={def_indent}")

        # Tìm hết phần thân hàm settings
        k = def_line + 1
        while k < n:
            l = lines[k]
            stripped = l.strip()
            indent = len(l) - len(l.lstrip(" "))
            if stripped != "" and indent <= def_indent and (
                stripped.startswith("@app.route(")
                or stripped.startswith("def ")
                or stripped.startswith("if __name__")
            ):
                break
            k += 1

        end = k
        print(f"[INFO] Block settings cũ: lines {start+1}..{end}")

        # Thay bằng block mới, gọn, chỉ render settings.html
        new_block = '''
@app.route("/settings", methods=["GET"])
def settings():
    """
    SECURITY_BUNDLE – Settings page.
    Hiển thị bảng BY TOOL / CONFIG từ static/last_tool_config.json.
    """
    import os, json
    from flask import render_template

    root = os.path.dirname(os.path.abspath(__file__))
    cfg_path = os.path.join(root, "static", "last_tool_config.json")

    cfg_data = []
    if os.path.exists(cfg_path):
        try:
            with open(cfg_path, "r", encoding="utf-8") as f:
                cfg_data = json.load(f)
        except Exception:
            # Nếu lỗi parse thì vẫn trả trang, JS phía client sẽ fetch API riêng
            cfg_data = []

    return render_template(
        "settings.html",
        cfg_path=cfg_path,
        cfg_data=cfg_data,
    )
'''

        out.append(new_block.lstrip("\n"))
        i = end
        continue

    else:
        out.append(line)
        i += 1

path.write_text("".join(out), encoding="utf-8")
print("[OK] Đã reset route /settings -> render settings.html.")
PY

echo "[DONE] patch_settings_route_reset.sh hoàn thành."
