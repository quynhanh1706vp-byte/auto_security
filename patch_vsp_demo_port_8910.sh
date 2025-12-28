#!/usr/bin/env bash
set -euo pipefail

APP_PY="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

echo "[PATCH] Đổi vsp_demo_app.py sang port 8910"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = p.read_text(encoding="utf-8")
orig = txt

# cố gắng replace các dạng phổ biến
patterns = [
    'port=8950',
    'port = 8950',
]

replaced = False
for pat in patterns:
    if pat in txt:
        txt = txt.replace(pat, 'port=8910')
        replaced = True

if not replaced and "app.run(" in txt:
    # fallback: nếu không có port rõ ràng, thêm port=8910
    import re
    def repl(m):
        inside = m.group(1)
        if "port=" in inside:
            return m.group(0)  # đã có port nhưng không phải 8950, không đụng
        return f"app.run({inside}port=8910, "
    txt_new = re.sub(r"app\.run\((.*?)\)", repl, txt, count=1, flags=re.S)
    if txt_new != txt:
        txt = txt_new
        replaced = True

if txt != orig:
    backup = p.with_suffix(p.suffix + ".bak_port_8950")
    backup.write_text(orig, encoding="utf-8")
    p.write_text(txt, encoding="utf-8")
    print("[PATCH] Đã sửa vsp_demo_app.py sang port 8910 (backup ->", backup.name, ")")
else:
    print("[PATCH] Không tìm thấy cấu hình port=8950 trong vsp_demo_app.py – không sửa gì.")
PY

echo "[PATCH] Done."
