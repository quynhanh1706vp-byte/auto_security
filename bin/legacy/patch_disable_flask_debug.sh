#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] Tắt Flask debug trong $APP"

python3 - "$APP" <<'PY'
from pathlib import Path

path = Path("app.py")
lines = path.read_text(encoding="utf-8").splitlines()

idx = None
for i, line in enumerate(lines):
    if "app.run(" in line:
        idx = i
# lấy lần xuất hiện cuối (gần cuối file)
if idx is None:
    print("[WARN] Không tìm thấy app.run( trong app.py – không patch gì.")
else:
    line = lines[idx]
    orig = line

    # Nếu có debug=... thì chuyển sang False
    if "debug=" in line:
        line = line.replace("debug=True", "debug=False")
        line = line.replace("debug = True", "debug = False")
    else:
        # Chèn debug=False, use_reloader=False trước dấu ')'
        pos = line.rfind(")")
        if pos != -1:
            before = line[:pos]
            after = line[pos:]
            if before.strip().endswith("("):
                line = before + "debug=False, use_reloader=False" + after
            else:
                line = before + ", debug=False, use_reloader=False" + after

    lines[idx] = line
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("[OK] app.run dòng cũ:")
    print("    ", orig)
    print("[OK] app.run dòng mới:")
    print("    ", line)
PY

echo "[DONE] patch_disable_flask_debug.sh hoàn thành."
