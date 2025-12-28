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

cp "$APP" "${APP}.bak_remove_settings_latest_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup app.py."

python3 - << 'PY'
from pathlib import Path

path = Path("app.py")
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

out = []
i = 0
n = len(lines)
removed_blocks = 0

while i < n:
    line = lines[i]
    s = line.replace("'", '"')
    if '@app.route' in s and '"/settings_latest"' in s:
        # Comment decorator + toàn bộ body của route này
        base_indent = len(line) - len(line.lstrip(" "))
        print(f"[INFO] Comment /settings_latest route tại line {i+1}")
        removed_blocks += 1
        while i < n:
            l = lines[i]
            if not l.lstrip().startswith("#"):
                out.append("# EXTRA_SETTINGS_LATEST_REMOVED " + l)
            else:
                out.append(l)
            i += 1
            if i >= n:
                break
            nxt = lines[i]
            stripped = nxt.strip()
            indent = len(nxt) - len(nxt.lstrip(" "))
            # gặp block top-level mới: dừng ở đây (để vòng while ngoài xử lý tiếp)
            if (
                stripped != ""
                and indent <= base_indent
                and (
                    stripped.startswith("@app.route(")
                    or stripped.startswith("def ")
                    or stripped.startswith("if __name__")
                )
            ):
                break
        continue
    else:
        out.append(line)
        i += 1

print(f"[INFO] Tổng số block /settings_latest đã comment: {removed_blocks}")
path.write_text("".join(out), encoding="utf-8")
PY

echo "[DONE] patch_remove_settings_latest_routes.sh hoàn thành."
