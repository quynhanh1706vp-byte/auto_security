#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[VSP_UI_DEV] ROOT = $ROOT"

# 1) Activate venv
if [ -f "$ROOT/../.venv/bin/activate" ]; then
  echo "[VSP_UI_DEV] Activating venv ../.venv"
  # shellcheck disable=SC1091
  source "$ROOT/../.venv/bin/activate"
elif [ -f "$ROOT/.venv/bin/activate" ]; then
  echo "[VSP_UI_DEV] Activating venv .venv"
  # shellcheck disable=SC1091
  source "$ROOT/.venv/bin/activate"
else
  echo "[VSP_UI_DEV][WARN] Không tìm thấy venv, dùng python system."
fi

# 2) Kill mọi thứ đang giữ port 8910
echo "[VSP_UI_DEV] Killing processes on port 8910 (if any)..."
fuser -k 8910/tcp 2>/dev/null || true

PID_8910="$(lsof -ti:8910 2>/dev/null || true)"
if [ -n "$PID_8910" ]; then
  echo "[VSP_UI_DEV] lsof: killing PID $PID_8910 on 8910"
  kill -9 $PID_8910 2>/dev/null || true
fi

# 3) Kill mọi python vsp_demo_app cũ (extra safe)
pkill -f "vsp_demo_app.py" 2>/dev/null || true
pkill -f "python vsp_demo_app" 2>/dev/null || true

# 4) Start vsp_demo_app.py (foreground)
echo "[VSP_UI_DEV] Starting vsp_demo_app.py on 8910..."
python "$ROOT/vsp_demo_app.py"
