#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_rootredir_${TS}"
echo "[BACKUP] ${GW}.bak_rootredir_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_ROOT_REDIRECT_TO_VSP5_MW_V1"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

addon = f"""

# {MARK}
class _VspRootRedirectToVsp5MW:
    def __init__(self, app, target="/vsp5"):
        self.app = app
        self.target = target
    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "").strip()
        if path == "" or path == "/":
            start_response("302 Found", [
                ("Location", self.target),
                ("Content-Type", "text/plain; charset=utf-8"),
                ("Content-Length", "0"),
            ])
            return [b""]
        return self.app(environ, start_response)

try:
    application.wsgi_app = _VspRootRedirectToVsp5MW(application.wsgi_app)
except Exception:
    pass
"""
p.write_text(s + addon, encoding="utf-8")
print("[OK] appended root redirect MW")
PY

echo "== py_compile =="
python3 -m py_compile "$GW" && echo "[OK] py_compile OK"

echo "== restart clean :8910 (nohup only) =="
rm -f /tmp/vsp_ui_8910.lock || true
PID="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1)"
[ -n "${PID:-}" ] && kill -9 "$PID" || true

: > out_ci/ui_8910.boot.log || true
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

sleep 1.2
echo "== smoke =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,12p'
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,12p'
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 180; echo
echo "== boot log tail =="
tail -n 60 out_ci/ui_8910.boot.log || true
