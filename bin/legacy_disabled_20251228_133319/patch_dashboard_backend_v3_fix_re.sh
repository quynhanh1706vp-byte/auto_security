#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = f.read()

old = "    import json, os\n    from pathlib import Path\n    from datetime import datetime\n"
new = "    import json, os, re\n    from pathlib import Path\n    from datetime import datetime\n"

if new in data:
    print("[INFO] Đã có import re rồi, bỏ qua.")
else:
    if old not in data:
        print("[ERR] Không tìm thấy block import json, os trong app.py")
        sys.exit(1)
    data = data.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(data)
    print("[OK] Đã thêm re vào import trong index().")
PY
