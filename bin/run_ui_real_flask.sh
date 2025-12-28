#!/usr/bin/env bash
set -e

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

echo "[INFO] PWD = $(pwd)"

# Kill mọi server cũ dùng port 8905 và my_flask_app nếu còn
echo "[INFO] Kill old Flask on 8905..."
fuser -k 8905/tcp 2>/dev/null || true
pkill -f "my_flask_app/app.py" 2>/dev/null || true

# Activate venv chuẩn
source ../.venv/bin/activate
echo "[INFO] Python = $(which python3)"

# Chạy app.py thật của SECURITY_BUNDLE
python3 app.py
