#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

CFG="/home/test/Data/SECURITY_BUNDLE/ui/config/production.env"
if [ -f "$CFG" ]; then
  set +u
  # shellcheck disable=SC1090
  source "$CFG"
  set -u
fi

HOST="${VSP_UI_HOST:-127.0.0.1}"
PORT="${VSP_UI_PORT:-8910}"
WORKERS="${VSP_UI_WORKERS:-2}"
APP="${VSP_UI_WSGI_APP:-wsgi_vsp_ui_gateway:app}"

VENV_GUNICORN="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn"
if [ -x "$VENV_GUNICORN" ]; then
  exec "$VENV_GUNICORN" -b "${HOST}:${PORT}" -w "${WORKERS}" "$APP"
fi

exec /usr/bin/python3 -m gunicorn -b "${HOST}:${PORT}" -w "${WORKERS}" "$APP"
