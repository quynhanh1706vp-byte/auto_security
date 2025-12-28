#!/usr/bin/env bash
set -e

echo "[i] Rebuild header sạch cho app.py (imports + ROOT/UI_DIR/PORT/OUT_DIR)..."

python3 - <<'PY'
import os

path = "app.py"

with open(path, "r", encoding="utf-8") as f:
    s = f.read()

marker = "app = Flask("
idx = s.find(marker)
if idx == -1:
    print("[ERR] Không tìm thấy 'app = Flask(' trong app.py, dừng.")
    raise SystemExit(1)

# Giữ nguyên toàn bộ body từ chỗ app = Flask(...) trở xuống
body = s[idx:]

header = """#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import json
import csv
import io
from datetime import datetime

from flask import (
    Flask,
    jsonify,
    request,
    send_file,
    send_from_directory,
    Response,
)

# --- Path config (auto patch v2) ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("ROOT", os.path.abspath(os.path.join(BASE_DIR, "..")))
UI_DIR = os.environ.get("UI_DIR", BASE_DIR)
PORT = int(os.environ.get("PORT", "8905"))
OUT_DIR = os.path.join(ROOT, "out")
# --- End path config (auto patch v2) ---

"""

with open(path, "w", encoding="utf-8") as f:
    f.write(header + body)

print("[OK] Đã rebuild header app.py sạch sẽ.")
PY
