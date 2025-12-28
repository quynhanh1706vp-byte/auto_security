#!/usr/bin/env bash
set -e

ROOT="/home/test/Data/SECURITY_BUNDLE"
UI_DIR="$ROOT/ui"
PORT="${PORT:-8905}"   # cho phép PORT=8910 ./run_ui.sh

echo "[i] ROOT  = $ROOT"
echo "[i] UI_DIR= $UI_DIR"
echo "[i] PORT  = $PORT"

echo "[i] Killing old process on port $PORT (if any)..."

# Cách 1: dùng fuser nếu có
if command -v fuser >/dev/null 2>&1; then
  fuser -k "${PORT}"/tcp 2>/dev/null || true
fi

# Cách 2: fallback dùng lsof
if command -v lsof >/dev/null 2>&1; then
  PIDS="$(lsof -ti tcp:"${PORT}" || true)"
  if [ -n "$PIDS" ]; then
    echo "[i] Found PIDs on port $PORT: $PIDS → killing..."
    kill -9 $PIDS 2>/dev/null || true
  fi
fi

cd "$UI_DIR"

# Kích hoạt venv nếu có
if [ -d ".venv" ]; then
  echo "[i] Using .venv"
  # shellcheck source=/dev/null
  source .venv/bin/activate
else
  echo "[WARN] .venv not found, using system python3"
fi

export FLASK_APP=app.py
export FLASK_ENV=development

python3 app.py
