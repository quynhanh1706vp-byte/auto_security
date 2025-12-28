#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

echo "[PATCH] Kéo thẳng block try:/except của datasource_v2 trong $APP"

python - << 'PY'
from pathlib import Path

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")
lines = txt.splitlines()

out = []
i = 0
n = len(lines)

while i < n:
    line = lines[i]

    # Tìm block '    try:' có chứa 'datasource_v2' ở 15 dòng kế tiếp
    if line.startswith("    try:") and "datasource_v2" in "\n".join(lines[i:i+15]):
        print(f"[PATCH] Found indented try block for datasource_v2 at line {i+1}")

        # Dỡ nguyên block này ra: bỏ 4 spaces ở đầu cho tất cả dòng liên quan
        while i < n:
            cur = lines[i]
            # Vẫn còn trong block nếu:
            #  - dòng rỗng, hoặc
            #  - dòng bắt đầu bằng 4 space (indent hiện tại), hoặc
            #  - dòng bắt đầu bằng '    except' / '    finally'
            if cur.startswith("    ") or not cur.strip():
                # Bỏ 4 spaces nếu có
                if cur.startswith("    "):
                    out.append(cur[4:])
                else:
                    out.append(cur)
                i += 1
            else:
                # Gặp dòng top-level mới => block kết thúc
                break
        continue

    out.append(line)
    i += 1

new_txt = "\n".join(out) + "\n"
app_path.write_text(new_txt, encoding="utf-8")
print("[OK] Đã ghi lại", app_path)
PY

echo "[PATCH] Done."
