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

cp "$APP" "${APP}.bak_dedupe_settings_func_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py (dedupe settings by func)."

python3 - << 'PY'
from pathlib import Path
import re

path = Path("app.py")
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

# Tìm tất cả dòng định nghĩa def settings(
settings_defs = []
for idx, line in enumerate(lines):
    if re.match(r'\s*def\s+settings\s*\(', line):
        settings_defs.append(idx)

print(f"[INFO] Tìm thấy {len(settings_defs)} hàm def settings().")

if len(settings_defs) <= 1:
    print("[INFO] <=1 hàm settings, không cần dedupe.")
else:
    # Giữ LẦN CUỐI, comment các hàm trước đó
    keep_idx = settings_defs[-1]
    print(f"[INFO] Sẽ giữ hàm settings() tại line {keep_idx+1}, comment {len(settings_defs)-1} hàm trước đó.")

    # Comment từ các def settings cũ trở lên (ngược từ trước về đầu)
    to_comment_blocks = settings_defs[:-1]

    out = []
    i = 0
    n = len(lines)

    # Tập các dòng def settings cũ để xử lý
    def_indices = set(to_comment_blocks)

    while i < n:
        if i in def_indices:
            # Đây là def settings cũ → comment cả decorator phía trên + body
            def_line = i
            def_indent = len(lines[i]) - len(lines[i].lstrip(" "))
            print(f"[INFO] Comment def settings cũ tại line {i+1} (indent={def_indent}).")

            # Tìm decorator @app.route phía trên (nếu có)
            start = def_line
            j = def_line - 1
            while j >= 0:
                l = lines[j]
                stripped = l.strip()
                if stripped.startswith("@"):
                    start = j
                    j -= 1
                    continue
                # gặp dòng trắng vẫn tiếp
                if stripped == "":
                    start = j
                    j -= 1
                    continue
                break

            # Từ start tới hết body của hàm
            end = def_line + 1
            while end < n:
                l = lines[end]
                stripped = l.strip()
                indent = len(l) - len(l.lstrip(" "))
                # kết thúc body khi gặp block top-level mới (indent <= def_indent)
                # và không phải dòng trắng
                if stripped != "" and indent <= def_indent:
                    break
                end += 1

            # Comment các dòng trong [start, end)
            for k in range(start, end):
                line_k = lines[k]
                if line_k.lstrip().startswith("#"):
                    out.append(line_k)  # đã là comment
                else:
                    out.append("# EXTRA_SETTINGS_FUNC_REMOVED " + line_k)
            i = end
        else:
            out.append(lines[i])
            i += 1

    path.write_text("".join(out), encoding="utf-8")
    print("[OK] Đã comment các hàm settings() cũ, chỉ giữ hàm cuối.")

PY

echo "[DONE] patch_dedupe_settings_by_func.sh hoàn thành."
