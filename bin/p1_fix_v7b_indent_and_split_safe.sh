#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl; need grep

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_v7b_${TS}"
echo "[BACKUP] ${GW}.bak_v7b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Remove the wrongly injected block that started with "# VSP_P1_APP_OBJECT_SPLIT_KEEPFLASK_V7"
#    (we remove until the first blank line after it, conservatively)
s2 = re.sub(
    r'(?s)\n?#\s*VSP_P1_APP_OBJECT_SPLIT_KEEPFLASK_V7.*?\n\n',
    '\n',
    s,
    count=1
)

# 2) Remove the restore block "VSP_P1_APP_OBJECT_SPLIT_APPLY_V7" if present (we'll reinsert cleanly)
s2 = re.sub(
    r'(?s)\n?#\s*VSP_P1_APP_OBJECT_SPLIT_APPLY_V7.*?\n\n',
    '\n',
    s2,
    count=1
)

# 3) Insert a SAFE split block at top-level after initial comments/shebang/encoding lines
lines = s2.splitlines(True)

ins = 0
for i, line in enumerate(lines[:60]):
    # keep shebang / coding / leading comments
    if line.startswith("#!") or re.match(r"^#.*coding[:=]", line) or line.lstrip().startswith("#") or line.strip()=="":
        ins = i + 1
        continue
    ins = i
    break

safe_block = (
    "# VSP_P1_APP_OBJECT_SPLIT_KEEPFLASK_V7B\n"
    "# Ensure 'application' stays a Flask app; build WSGI middleware chain in _vsp_wsgi_app.\n"
    "_vsp_flask_app = None\n"
    "_vsp_wsgi_app = None\n"
    "def _vsp_capture_flask_app(obj):\n"
    "    global _vsp_flask_app, _vsp_wsgi_app\n"
    "    if _vsp_flask_app is None and obj is not None and hasattr(obj, 'after_request'):\n"
    "        _vsp_flask_app = obj\n"
    "        _vsp_wsgi_app = getattr(obj, 'wsgi_app', obj)\n"
    "\n"
)

lines.insert(ins, safe_block)
s3 = "".join(lines)

# 4) Rewrite any top-level 'application = ...' overwrites into building _vsp_wsgi_app.
#    We do this line-by-line, safe and simple.
out = []
n_rewrite = 0
for line in s3.splitlines(True):
    m = re.match(r'^([ \t]*)application\s*=\s*(.+)$', line)
    if not m:
        out.append(line); continue
    indent, rhs = m.group(1), m.group(2).rstrip()

    # keep the canonical restore line if present later (we will re-add a clean restore anyway)
    if rhs.strip() in ("_vsp_flask_app",):
        out.append(line); continue

    # capture flask app before any overwrites
    out.append(f"{indent}_vsp_capture_flask_app(application)\n")

    # rewrite function assignment special-case
    if re.match(r'^\s*_vsp_force_default_to_vsp5\s*$', rhs):
        out.append(f"{indent}_vsp_wsgi_app = _vsp_force_default_to_vsp5(_vsp_wsgi_app)\n")
        n_rewrite += 1
        continue

    # if it is a call, replace first arg application/app with _vsp_wsgi_app
    if "(" in rhs:
        rhs2 = rhs
        rhs2 = re.sub(r'\(\s*application(\s*(?:,|\)))', r'(_vsp_wsgi_app\1', rhs2)
        rhs2 = re.sub(r'\(\s*app(\s*(?:,|\)))', r'(_vsp_wsgi_app\1', rhs2)
        rhs2 = re.sub(r'([,(]\s*)application(\s*[,)\]])', r'\1_vsp_wsgi_app\2', rhs2)
        rhs2 = re.sub(r'([,(]\s*)app(\s*[,)\]])', r'\1_vsp_wsgi_app\2', rhs2)
        out.append(f"{indent}_vsp_wsgi_app = {rhs2}\n")
        n_rewrite += 1
        continue

    # otherwise just move to wsgi chain, never overwrite flask app
    out.append(f"{indent}_vsp_wsgi_app = {rhs}\n")
    n_rewrite += 1

s4 = "".join(out)

# 5) Rewrite "application.wsgi_app = ..." into "_vsp_wsgi_app = ..." (and replace application.wsgi_app references)
s4 = re.sub(r'(?m)^([ \t]*)application\.wsgi_app\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*application\.wsgi_app',
            r'\1_vsp_capture_flask_app(application)\n\1_vsp_wsgi_app = \2(_vsp_wsgi_app', s4)
s4 = s4.replace("application.wsgi_app", "_vsp_wsgi_app")

# 6) Before first decorator, restore Flask app + attach wsgi chain
decor = re.search(r'(?m)^\s*@application\.', s4)
restore = (
    "\n# VSP_P1_APP_OBJECT_SPLIT_APPLY_V7B\n"
    "_vsp_capture_flask_app(globals().get('application', None))\n"
    "if _vsp_flask_app is not None:\n"
    "    application = _vsp_flask_app\n"
    "    try:\n"
    "        application.wsgi_app = _vsp_wsgi_app\n"
    "    except Exception:\n"
    "        pass\n\n"
)
if decor:
    s4 = s4[:decor.start()] + restore + s4[decor.start():]
else:
    s4 += restore

p.write_text(s4, encoding="utf-8")
print(f"[OK] v7b applied; rewrote application= lines: {n_rewrite}")
PY

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
