#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

bad=0

echo "== check: app = application (should not exist) =="
if grep -RIn --line-number -E '^\s*app\s*=\s*application\s*$' "$F" >/dev/null; then
  grep -RIn --line-number -E '^\s*app\s*=\s*application\s*$' "$F" | head -n 50
  bad=1
else
  echo "[OK] no 'app = application'"
fi

echo "== check: app = None (high risk) =="
if grep -RIn --line-number -E '^\s*app\s*=\s*None\s*$' "$F" >/dev/null; then
  grep -RIn --line-number -E '^\s*app\s*=\s*None\s*$' "$F" | head -n 50
  bad=1
else
  echo "[OK] no 'app = None'"
fi

echo "== check: wrapper assigns to app (prefer application = wrap(application)) =="
if grep -RIn --line-number -E '^\s*app\s*=\s*[A-Za-z_][A-Za-z0-9_\.]*\(\s*app\b' "$F" >/dev/null; then
  grep -RIn --line-number -E '^\s*app\s*=\s*[A-Za-z_][A-Za-z0-9_\.]*\(\s*app\b' "$F" | head -n 80
  bad=1
else
  echo "[OK] no 'app = wrap(app)' pattern"
fi

[ "$bad" -eq 0 ] || { echo "[ERR] wsgi app reassign patterns found"; exit 2; }
echo "[OK] gate passed"
