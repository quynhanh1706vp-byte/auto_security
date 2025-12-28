#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl; need grep

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_app_object_split_v6_${TS}"
echo "[BACKUP] ${GW}.bak_app_object_split_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_APP_OBJECT_SPLIT_KEEPFLASK_V6"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 0) Insert split variables right after Flask app creation (application = Flask(...))
m = re.search(r'(?m)^(?P<indent>[ \t]*)application\s*=\s*Flask\s*\(.*$', s)
if not m:
    # fallback: app = Flask(...); later code uses "application"
    m2 = re.search(r'(?m)^(?P<indent>[ \t]*)app\s*=\s*Flask\s*\(.*$', s)
    if not m2:
        raise SystemExit("[ERR] cannot find Flask() creation line for application/app")
    # Insert after app=Flask; also ensure application points to app if exists later (we will rebind before decorators anyway)
    ins_pos = m2.end()
    inject = "\n# " + MARK + "\n_vsp_flask_app = app\n_vsp_wsgi_app = app.wsgi_app\n"
    s = s[:ins_pos] + inject + s[ins_pos:]
else:
    ins_pos = m.end()
    inject = "\n# " + MARK + "\n_vsp_flask_app = application\n_vsp_wsgi_app = application.wsgi_app\n"
    s = s[:ins_pos] + inject + s[ins_pos:]

# 1) Rewrite ANY middleware assignment that overwrites application, where middleware name contains MW / WSGI / Middleware anywhere
#    application = Something(...application...)
# -> _vsp_wsgi_app = Something(..._vsp_wsgi_app...)
head_pat = re.compile(r'(?m)^(?P<indent>[ \t]*)application\s*=\s*(?P<mw>[A-Za-z_][A-Za-z0-9_]*(?:MW|WSGI|Middleware)[A-Za-z0-9_]*)\s*\(')
s, n1 = head_pat.subn(r'\g<indent>_vsp_wsgi_app = \g<mw>(', s)

arg_pat = re.compile(r'([A-Za-z_][A-Za-z0-9_]*(?:MW|WSGI|Middleware)[A-Za-z0-9_]*\s*\(\s*)application(\s*(?:,|\)))', flags=re.S)
s, n2 = arg_pat.subn(r'\1_vsp_wsgi_app\2', s)

# 2) Rewrite application.wsgi_app assignments to use _vsp_wsgi_app (prevents crash if application temporarily not Flask)
#    application.wsgi_app = X(application.wsgi_app, ...)
# -> _vsp_wsgi_app = X(_vsp_wsgi_app, ...)
s, n3 = re.subn(r'(?m)^(?P<indent>[ \t]*)application\.wsgi_app\s*=\s*(?P<mw>[A-Za-z_][A-Za-z0-9_]*)\s*\(\s*application\.wsgi_app',
                r'\g<indent>_vsp_wsgi_app = \g<mw>(_vsp_wsgi_app', s)

# 3) Before first @application.after_request, force application back to Flask app and attach final wsgi chain
anchor = re.search(r'(?m)^\s*@application\.after_request\s*$', s)
if anchor:
    pre = s[:anchor.start()]
    post = s[anchor.start():]
    fix_block = (
        "\n# VSP_P1_APP_OBJECT_SPLIT_APPLY_V6\n"
        "try:\n"
        "    application = _vsp_flask_app\n"
        "except Exception:\n"
        "    application = globals().get('application', globals().get('app'))\n"
        "try:\n"
        "    application.wsgi_app = _vsp_wsgi_app\n"
        "except Exception:\n"
        "    pass\n"
    )
    s = pre + fix_block + post
else:
    # If no after_request, still ensure at end
    s += (
        "\n# VSP_P1_APP_OBJECT_SPLIT_APPLY_V6\n"
        "try:\n"
        "    application = _vsp_flask_app\n"
        "    application.wsgi_app = _vsp_wsgi_app\n"
        "except Exception:\n"
        "    pass\n"
    )

p.write_text(s, encoding="utf-8")
print(f"[OK] rewrites: head={n1} arg={n2} wsgi_assign={n3}")
PY

echo "== quick checks =="
echo "-- remaining 'application = .*MW' (should be 0) --"
grep -nE '^\s*application\s*=\s*.*(MW|WSGI|Middleware)' "$GW" | head -n 50 || true

echo "== py_compile =="
python3 -m py_compile "$GW" && echo "[OK] py_compile OK"

echo "== kill lock/listener (NO sudo) =="
rm -f /tmp/vsp_ui_8910.lock || true
PID="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1)"
if [ -n "${PID:-}" ]; then
  echo "[INFO] killing pid=${PID} on :8910"
  kill -9 "$PID" || true
fi

echo "== start gunicorn :8910 (nohup only) =="
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

echo "== import check =="
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
