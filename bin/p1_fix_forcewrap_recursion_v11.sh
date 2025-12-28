#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl; need grep

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_forcewrap_recursion_${TS}"
echo "[BACKUP] ${GW}.bak_forcewrap_recursion_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_FIX_FORCEWRAP_RECURSION_V11"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) Ensure ForceWrapReportsRunFile wraps a WSGI callable, not a Flask app object.
# Replace:
#   application.wsgi_app = _ForceWrapReportsRunFileMW(_orig_app)
# with:
#   _fw_rrf_arg = _orig_app
#   _fw_rrf_wsgi = getattr(_fw_rrf_arg, "wsgi_app", _fw_rrf_arg)
#   application.wsgi_app = _ForceWrapReportsRunFileMW(_fw_rrf_wsgi)
pat_rrf = re.compile(
    r'(?m)^(?P<indent>[ \t]*)application\.wsgi_app\s*=\s*_ForceWrapReportsRunFileMW\((?P<arg>[^)]+)\)\s*$'
)
def repl_rrf(m):
    ind = m.group("indent")
    arg = m.group("arg").strip()
    return (
        f"{ind}# {MARK}\n"
        f"{ind}_fw_rrf_arg = {arg}\n"
        f"{ind}_fw_rrf_wsgi = getattr(_fw_rrf_arg, 'wsgi_app', _fw_rrf_arg)\n"
        f"{ind}application.wsgi_app = _ForceWrapReportsRunFileMW(_fw_rrf_wsgi)"
    )
s, n1 = pat_rrf.subn(repl_rrf, s)

# 2) Also guard ForceWrapRunsAlways200 if someone accidentally passed "application" (Flask) instead of "application.wsgi_app".
pat_runs = re.compile(
    r'(?m)^(?P<indent>[ \t]*)application\.wsgi_app\s*=\s*_ForceWrapRunsAlways200MW\(\s*application\s*(?P<rest>,[^)]*)?\)\s*$'
)
s, n2 = pat_runs.subn(
    lambda m: f"{m.group('indent')}# {MARK}\n{m.group('indent')}application.wsgi_app = _ForceWrapRunsAlways200MW(application.wsgi_app{m.group('rest') or ''})",
    s
)

p.write_text(s, encoding="utf-8")
print(f"[OK] patched: ForceWrapReportsRunFileMW={n1}, ForceWrapRunsAlways200MW={n2}")
PY

echo "== py_compile =="
python3 -m py_compile "$GW" && echo "[OK] py_compile OK"

echo "== restart clean :8910 (nohup only) =="
rm -f /tmp/vsp_ui_8910.lock || true
PID="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1)"
[ -n "${PID:-}" ] && kill -9 "$PID" || true

: > out_ci/ui_8910.boot.log || true
: > out_ci/ui_8910.error.log || true

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

sleep 1.2
echo "== smoke =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,12p'
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,20p'

echo "== if still 500, show top of error log =="
tail -n 80 out_ci/ui_8910.error.log || true
