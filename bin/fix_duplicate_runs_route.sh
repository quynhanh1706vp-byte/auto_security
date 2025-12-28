#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

python3 - <<'PY'
from pathlib import Path
import re

path = Path("app.py")
data = path.read_text(encoding="utf-8")

# Tìm tất cả block dạng:
# @app.route("/runs")
# def runs_page(...):
pat = re.compile(r'@app\.route\("/runs"[^\n]*\)\s*def runs_page\([^)]*\):', re.MULTILINE)
matches = list(pat.finditer(data))
print(f"[INFO] found {len(matches)} /runs routes")

if len(matches) <= 1:
    print("[INFO] Không có route trùng, không cần sửa.")
    raise SystemExit(0)

# Giữ block đầu tiên (mới), xoá các block phía sau
starts = [m.start() for m in matches]
starts_sorted = sorted(starts)

def find_block_end(text: str, start_pos: int) -> int:
    """
    Kết thúc 1 block route = trước route kế tiếp hoặc trước
    'if __name__ == "__main__"' hoặc hết file.
    """
    next_route = text.find("\n@app.route(", start_pos + 1)
    main_guard = text.find('\nif __name__ == "__main__"', start_pos + 1)
    candidates = [p for p in (next_route, main_guard) if p != -1]
    return min(candidates) if candidates else len(text)

blocks = []
for s in starts_sorted:
    e = find_block_end(data, s)
    blocks.append((s, e))

# Xoá tất cả block trừ block đầu
blocks_to_del = [(s, e) for i, (s, e) in enumerate(blocks) if i > 0]

for s, e in sorted(blocks_to_del, reverse=True):
    print(f"[INFO] Removing old runs_page block at [{s}:{e}]")
    data = data[:s] + "\n# [OLD runs_page removed]\n" + data[e:]

path.write_text(data, encoding="utf-8")
print("[OK] Đã xoá route /runs cũ, giữ lại đúng 1 runs_page.")
PY
