#!/usr/bin/env bash
set -e

ROOT="/home/test/Data/SECURITY_BUNDLE/ui/my_flask_app/my_flask_app"
cd "$ROOT"

# Tìm backup app.py
APP_BAK=$(ls -1 app.py.bak_* 2>/dev/null | sort | tail -1 || true)
# Tìm backup index.html trong templates/
TPL_BAK=$(ls -1 templates/index.html.bak_* 2>/dev/null | sort | tail -1 || true)

echo "[INFO] APP_BAK=$APP_BAK"
echo "[INFO] TPL_BAK=$TPL_BAK"

if [ -n "$APP_BAK" ]; then
  cp "$APP_BAK" app.py
  echo "[OK] Đã khôi phục app.py từ $APP_BAK"
else
  echo "[WARN] Không tìm thấy app.py.bak_* để khôi phục"
fi

if [ -n "$TPL_BAK" ]; then
  cp "$TPL_BAK" templates/index.html
  echo "[OK] Đã khôi phục templates/index.html từ $TPL_BAK"
else
  echo "[WARN] Không tìm thấy templates/index.html.bak_* để khôi phục"
fi
