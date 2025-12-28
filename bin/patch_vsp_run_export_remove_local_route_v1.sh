#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$UI_ROOT/vsp_demo_app.py"

if [[ ! -f "$TARGET" ]]; then
  echo "[ERR] Không tìm thấy $TARGET"
  exit 1
fi

BACKUP="${TARGET}.bak_run_export_remove_local_$(date +%Y%m%d_%H%M%S)"
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
removed_blocks = 0

while i < len(lines):
    line = lines[i]
    stripped = line.lstrip()

    # Bỏ block bắt đầu từ @app.route("/api/vsp/run_export_v3", ...)
    if '@app.route("/api/vsp/run_export_v3"' in line or "@app.route('/api/vsp/run_export_v3'" in line:
        removed_blocks += 1
        i += 1
        # skip cho đến khi gặp decorator khác hoặc if __main__
        while i < len(lines):
            s = lines[i].lstrip()
            if s.startswith('@app.route(') or s.startswith('if __name__ == "__main__":'):
                break
            i += 1
        continue

    # Nếu còn def vsp_run_export_v3(...) không có decorator (phòng trường hợp tách ra)
    if stripped.startswith('def vsp_run_export_v3('):
        removed_blocks += 1
        i += 1
        while i < len(lines):
            s = lines[i].lstrip()
            if s.startswith('@app.route(') or s.startswith('if __name__ == "__main__":'):
                break
            i += 1
        continue

    clean_lines.append(line)
    i += 1

print(f"[INFO] Removed {removed_blocks} local run_export_v3 block(s)")

cleaned_txt = "\n".join(clean_lines) + "\n"
target.write_text(cleaned_txt, encoding="utf-8")
PY

echo "[OK] Đã gỡ route local /api/vsp/run_export_v3 khỏi vsp_demo_app.py (chỉ còn dùng blueprint)."
