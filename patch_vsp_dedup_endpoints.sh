#!/usr/bin/env bash
set -euo pipefail

PY_FILE="vsp_demo_app.py"

echo "[i] Backup file gốc..."
cp "$PY_FILE" "${PY_FILE}.bak.dedup_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path
import re

path = Path("vsp_demo_app.py")
text = path.read_text(encoding="utf-8")

def dedup_endpoint(text: str, route: str, func: str, keep: str = "first") -> str:
    """
    Xóa bớt các block @app.route(...) def func(...) trùng nhau.
    - route: "/api/vsp/runs_index"
    - func:  "api_vsp_runs_index"
    - keep:  "first" hoặc "last"
    """
    pattern = (
        r'\n@app\.route\("'
        + re.escape(route)
        + r'"[^)]*\)[\s\S]*?def '
        + re.escape(func)
        + r'\([^)]*\):[\s\S]*?(?=\n@app\.route|\n# =======|$)'
    )

    matches = list(re.finditer(pattern, text, flags=re.S))
    if len(matches) <= 1:
        return text  # không có hoặc chỉ 1 -> OK

    if keep == "first":
        keep_idx = 0
    else:
        keep_idx = len(matches) - 1

    chars = list(text)
    for idx, m in enumerate(matches):
        if idx == keep_idx:
            continue
        for i in range(m.start(), m.end()):
            chars[i] = ""

    new_text = "".join(chars)
    return new_text

# 1) runs_index: giữ bản đầu tiên
text = dedup_endpoint(text, "/api/vsp/runs_index", "api_vsp_runs_index", keep="first")

# 2) datasource: giữ bản cuối cùng (override CLEAN VERSION ở cuối file)
text = dedup_endpoint(text, "/api/vsp/datasource", "api_vsp_datasource", keep="last")

path.write_text(text, encoding="utf-8")
PY

echo "[OK] Đã dedup endpoint /api/vsp/runs_index và /api/vsp/datasource."
