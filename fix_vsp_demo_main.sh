#!/usr/bin/env bash
set -euo pipefail

PY_FILE="vsp_demo_app.py"

echo "[i] Backup file gốc..."
cp "$PY_FILE" "${PY_FILE}.bak.main_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path
import re

path = Path("vsp_demo_app.py")
text = path.read_text(encoding="utf-8")

# 1) Xóa mọi block main cũ (nếu có)
text = re.sub(
    r'\nif __name__ == [\'"]__main__[\'"]:[\s\S]*$',
    '',
    text,
    flags=re.S,
)

# 2) Thêm main block mới đơn giản
block = '''
if __name__ == "__main__":
    # Dev server cho VSP demo
    app.run(host="0.0.0.0", port=8910, debug=False)
'''

text = text.rstrip() + block + "\n"
path.write_text(text, encoding="utf-8")
PY

echo "[OK] Đã thêm lại main block app.run(...) ở cuối vsp_demo_app.py."
