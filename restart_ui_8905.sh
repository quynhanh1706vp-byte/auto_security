#!/usr/bin/env bash
set -e

# Về đúng thư mục UI
cd /home/test/Data/SECURITY_BUNDLE/ui

# Activate venv
. .venv/bin/activate

# Set biến Flask
export FLASK_APP=app.py
export FLASK_ENV=development

# Nếu có process đang chiếm port 8905 thì kill trước
if fuser 8905/tcp >/dev/null 2>&1; then
  echo "[i] Đang kill server cũ trên port 8905..."
  fuser -k 8905/tcp
  sleep 1
fi

echo "[i] Start Flask trên port 8905..."
flask run -h 0.0.0.0 -p 8905
