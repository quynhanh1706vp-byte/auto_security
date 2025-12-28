#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl; need grep

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_legacycompat_safe_${TS}"
echo "[BACKUP] ${GW}.bak_legacycompat_safe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_LEGACYCOMPAT_SAFE_WRAP_V10"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

target = "application.wsgi_app = _VspRunFileLegacyCompatMW(application.wsgi_app)"
if target not in s:
    print("[ERR] target line not found. showing near matches:")
    for m in re.finditer(r"_VspRunFileLegacyCompatMW", s):
        start = max(0, m.start()-120)
        end = min(len(s), m.end()+120)
        print(s[start:end].replace("\n","\\n"))
        break
    raise SystemExit(2)

safe_block = (
f"# {MARK}\n"
"try:\n"
"    # Ensure application is a Flask app if possible (restore from global 'app' if it exists)\n"
"    _flask = application if hasattr(application, 'after_request') else globals().get('app', None)\n"
"    if _flask is not None and hasattr(_flask, 'after_request'):\n"
"        application = _flask\n"
"        application.wsgi_app = _VspRunFileLegacyCompatMW(application.wsgi_app)\n"
"except Exception:\n"
"    # If we can't safely wrap, skip instead of crashing import/boot.\n"
"    pass"
)

s2 = s.replace(target, safe_block, 1)
p.write_text(s2, encoding="utf-8")
print("[OK] patched legacy compat wrap safely")
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
echo "== ss :8910 =="
ss -ltnp | grep ':8910' || true

echo "== import check (must not crash) =="
python3 - <<'PY'
import wsgi_vsp_ui_gateway as m
print("[OK] imported")
print("type(application) =", type(m.application))
print("has after_request =", hasattr(m.application, "after_request"))
PY

echo "== smoke =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,12p'
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 220; echo
echo "== boot log tail =="
tail -n 120 out_ci/ui_8910.boot.log || true
