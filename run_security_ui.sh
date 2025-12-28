#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

echo "[UI] Start SECURITY_BUNDLE UI (Flask) trên port 8905 ..."

if [ -d ".venv" ]; then
  # nếu có virtualenv thì activate
  . .venv/bin/activate
fi

export FLASK_ENV=development

python3 app.py
