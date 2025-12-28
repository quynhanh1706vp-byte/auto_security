#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_fix_runsalways200_${TS}"
echo "[BACKUP] ${GW}.bak_fix_runsalways200_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P1_FIX_RUNSALWAYS200_KEEP_FLASK_V2"

if MARK in s:
    print("[OK] marker already present, skip")
    raise SystemExit(0)

# Fix ANY assignment that replaces Flask app object:
#   application = _ForceWrapRunsAlways200MW(...)
# -> application.wsgi_app = _ForceWrapRunsAlways200MW(application.wsgi_app)
pat = re.compile(
    r'^(?P<ind>\s*)application\s*=\s*_ForceWrapRunsAlways200MW\s*\(\s*(?P<arg>[^)]*)\s*\)\s*$',
    re.M
)

def repl(m):
    ind = m.group("ind")
    return (
        f"{ind}# {MARK}\n"
        f"{ind}# keep Flask app; wrap only WSGI callable\n"
        f"{ind}application.wsgi_app = _ForceWrapRunsAlways200MW(application.wsgi_app)"
    )

s2, n = pat.subn(repl, s)

# Extra safety: also fix compact style "application=_ForceWrapRunsAlways200MW(application)"
if n == 0:
    pat2 = re.compile(r'(?m)^(?P<ind>\s*)application=_ForceWrapRunsAlways200MW\([^)]*\)\s*$')
    s2, n2 = pat2.subn(lambda m: repl(m), s)
    n += n2

print(f"[OK] rewired RunsAlways200 assignment lines: {n}")

# If still 0 => show context so you can see what format it is
if n == 0:
    lines = s.splitlines()
    hits = [i for i,l in enumerate(lines,1) if "_ForceWrapRunsAlways200MW" in l]
    print("[WARN] no direct assignment matched. hits:", hits[:20])
    # Write a more aggressive fix: replace ANY "application = _ForceWrapRunsAlways200MW(" token
    s3, n3 = re.subn(r'(?m)^\s*application\s*=\s*_ForceWrapRunsAlways200MW\s*\(.*\)\s*$', lambda m: repl(m), s)
    if n3:
        s2 = s3
        n = n3
        print(f"[OK] aggressive rewrite matched: {n3}")

p.write_text(s2, encoding="utf-8")
PY

echo "== py_compile =="
python3 -m py_compile "$GW" && echo "[OK] py_compile OK"

echo "== kill lock/listener (NO sudo) =="
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

echo "== import check (must not crash) =="
python3 - <<'PY'
import wsgi_vsp_ui_gateway as m
print("application type:", type(m.application))
PY

echo "== smoke =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,10p'
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,10p'
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 220; echo

echo "== boot tail =="
tail -n 120 out_ci/ui_8910.boot.log || true
echo "== error tail =="
tail -n 120 out_ci/ui_8910.error.log || true

echo "[NEXT] Open Incognito /vsp5"
