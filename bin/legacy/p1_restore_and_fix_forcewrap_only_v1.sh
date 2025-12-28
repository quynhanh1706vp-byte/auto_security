#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ls; need tail; need ss; need awk; need sed; need pkill || true

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

echo "== pick backup =="
BKP="$(ls -1t ${GW}.bak_keepflask_* 2>/dev/null | head -n1 || true)"
if [ -z "${BKP}" ]; then
  echo "[ERR] no backup ${GW}.bak_keepflask_* found. List backups:"
  ls -1 ${GW}.bak_* 2>/dev/null | tail -n 20 || true
  exit 2
fi
echo "[INFO] restore from: $BKP"
cp -f "$BKP" "$GW"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_forcewrap_only_${TS}"
echo "[BACKUP] ${GW}.bak_forcewrap_only_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# ONLY fix internal ForceWrap middlewares that should NOT replace Flask app object.
# Replace:
#   application = _ForceWrapXXXMW(application)
# with:
#   application.wsgi_app = _ForceWrapXXXMW(application.wsgi_app)
pat = re.compile(r'^(?P<ind>\s*)application\s*=\s*(?P<cls>_ForceWrap[A-Za-z0-9_]*MW)\(\s*application\s*\)\s*$', re.M)

def repl(m):
    ind = m.group("ind")
    cls = m.group("cls")
    return (
        f"{ind}# [P1 FIX] keep Flask app; wrap only WSGI callable\n"
        f"{ind}application.wsgi_app = {cls}(application.wsgi_app)"
    )

s2, n = pat.subn(repl, s)
print(f"[OK] rewired ForceWrap MW lines: {n}")

p.write_text(s2, encoding="utf-8")
PY

echo "== py_compile =="
python3 -m py_compile "$GW" && echo "[OK] py_compile OK"

echo "== cleanup port/lock =="
rm -f /tmp/vsp_ui_8910.lock || true
pids="$(ss -ltnp | awk '/:8910/ {print $0}' | sed -n 's/.*pid=\\([0-9]\\+\\).*/\\1/p' | sort -u)"
if [ -n "${pids:-}" ]; then
  echo "[INFO] killing pids: $pids"
  kill -9 $pids 2>/dev/null || true
fi

echo "== start gunicorn :8910 =="
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

echo "== ss :8910 =="
ss -ltnp | grep ':8910' || true

echo "== quick import check (prints type) =="
python3 - <<'PY' || true
import wsgi_vsp_ui_gateway as m
print("application type:", type(getattr(m, "application", None)))
PY

echo "== smoke (non-fatal) =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,10p' || true
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,10p' || true
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 260; echo || true

echo "== boot tail =="
tail -n 120 out_ci/ui_8910.boot.log || true
echo "== error tail =="
tail -n 120 out_ci/ui_8910.error.log || true

echo "[NEXT] Nếu ss không thấy :8910 => nhìn 120 dòng boot/error ở trên sẽ ra lỗi import cụ thể."
echo "[NEXT] Nếu :8910 OK => mở Incognito /vsp5."
