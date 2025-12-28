#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need curl

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_keepflask_${TS}"
echo "[BACKUP] ${GW}.bak_keepflask_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Fix any pattern: application = SomeMW(application)
# -> application.wsgi_app = SomeMW(application.wsgi_app)
pat = re.compile(r'^(?P<indent>\s*)application\s*=\s*(?P<cls>[A-Za-z_][A-Za-z0-9_]*)\(\s*application\s*\)\s*$', re.M)

def repl(m):
    ind = m.group("indent")
    cls = m.group("cls")
    return (
        f"{ind}# [AUTO-FIX keep Flask app] wrap WSGI callable, not the Flask app\n"
        f"{ind}application.wsgi_app = {cls}(application.wsgi_app)"
    )

s2, n = pat.subn(repl, s)

if n == 0:
    print("[WARN] no 'application = X(application)' line found. Nothing changed.")
else:
    print(f"[OK] rewired {n} middleware wrap(s) to application.wsgi_app")

p.write_text(s2, encoding="utf-8")
PY

echo "== py_compile =="
python3 -m py_compile "$GW" && echo "[OK] py_compile OK"

echo "== kill stale lock + listeners =="
rm -f /tmp/vsp_ui_8910.lock || true
pids="$(ss -ltnp | awk '/:8910/ {print $0}' | sed -n 's/.*pid=\\([0-9]\\+\\).*/\\1/p' | sort -u)"
if [ -n "${pids:-}" ]; then
  echo "[INFO] killing pids: $pids"
  kill -9 $pids 2>/dev/null || true
fi

echo "== start gunicorn :8910 (NO sudo) =="
: > out_ci/ui_8910.boot.log  || true
: > out_ci/ui_8910.error.log || true
: > out_ci/ui_8910.access.log|| true

nohup ./.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 \
  --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui \
  --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log \
  --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

sleep 1.2
echo "== smoke =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,8p' || true
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,8p' || true
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 220; echo
echo "== boot tail =="
tail -n 80 out_ci/ui_8910.boot.log || true
echo "== error tail =="
tail -n 80 out_ci/ui_8910.error.log || true

echo "[NEXT] Mở Incognito /vsp5 hoặc Ctrl+F5."
