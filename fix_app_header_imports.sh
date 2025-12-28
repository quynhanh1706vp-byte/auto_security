#!/usr/bin/env bash
set -e

echo "[i] Reset phần import/header trong app.py..."

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

body = s[idx:]  # giữ nguyên toàn bộ phần thân từ app = Flask(...) trở xuống

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

"""

with open(path, "w", encoding="utf-8") as f:
    f.write(header + body)

print("[OK] Đã reset phần import/header trong app.py")
PY
