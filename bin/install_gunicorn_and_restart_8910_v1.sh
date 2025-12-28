#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# Prefer UI venv python if exists, else fallback to current python
PYBIN=""
if [ -x "/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3" ]; then
  PYBIN="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"
elif [ -x "/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python" ]; then
  PYBIN="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
else
  PYBIN="$(command -v python3 || command -v python)"
fi

echo "[INFO] using python: $PYBIN"
"$PYBIN" -V

echo "== check gunicorn =="
if "$PYBIN" -m pip show gunicorn >/dev/null 2>&1; then
  echo "[OK] gunicorn already installed"
else
  echo "[INSTALL] gunicorn"
  "$PYBIN" -m pip install -U pip wheel setuptools >/dev/null
  "$PYBIN" -m pip install gunicorn
fi

echo "== verify gunicorn import =="
"$PYBIN" -c "import gunicorn; print('gunicorn_version=', gunicorn.__version__)"

echo "== restart 8910 =="
rm -f out_ci/ui_8910.lock
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh

echo "== listening? =="
ss -lntp | grep ':8910' || echo "8910 still not listening"
