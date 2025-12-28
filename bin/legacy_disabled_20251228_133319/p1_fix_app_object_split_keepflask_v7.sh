#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl; need grep

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_app_object_split_v7_${TS}"
echo "[BACKUP] ${GW}.bak_app_object_split_v7_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_APP_OBJECT_SPLIT_KEEPFLASK_V7"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Find first "application =" assignment that overwrites application (your first is around line 450)
m = re.search(r'(?m)^(?P<indent>[ \t]*)application\s*=\s*.+$', s)
if not m:
    raise SystemExit("[ERR] cannot find any 'application =' line to anchor injection")

anchor = m.start()

inject = (
    f"# {MARK}\n"
    "# Keep Flask app object separate from WSGI chain.\n"
    "# At this point, 'application' must already exist (imported/created earlier).\n"
    "_vsp_flask_app = application\n"
    "_vsp_wsgi_app = getattr(application, 'wsgi_app', application)\n"
    "\n"
)

s = s[:anchor] + inject + s[anchor:]

# 1) Rewrite "application.wsgi_app = X(application.wsgi_app ...)" -> "_vsp_wsgi_app = X(_vsp_wsgi_app ...)"
s, n_w1 = re.subn(
    r'(?m)^(?P<indent>[ \t]*)application\.wsgi_app\s*=\s*(?P<fn>[A-Za-z_][A-Za-z0-9_]*)\s*\(\s*application\.wsgi_app',
    r'\g<indent>_vsp_wsgi_app = \g<fn>(_vsp_wsgi_app',
    s
)
s, n_w2 = re.subn(r'application\.wsgi_app', r'_vsp_wsgi_app', s)

# 2) Rewrite ANY "application = <call>(...)" into "_vsp_wsgi_app = <call>(...)" and also swap args
#    - replace "(application" or "( app" as first arg with "(_vsp_wsgi_app"
#    - replace ", application" or ", app" with ", _vsp_wsgi_app"
#
# Do it in a safe-ish way: only for lines that are assignments to application.
def rewrite_app_assignments(text: str):
    out = []
    nA = 0
    for line in text.splitlines(True):
        m = re.match(r'^([ \t]*)application\s*=\s*(.+)$', line)
        if not m:
            out.append(line); continue
        indent, rhs = m.group(1), m.group(2)

        # Special toxic line: "application = _vsp_force_default_to_vsp5" (no call) -> call it on wsgi chain
        if re.match(r'^\s*_vsp_force_default_to_vsp5\s*$', rhs.strip()):
            out.append(f"{indent}_vsp_wsgi_app = _vsp_force_default_to_vsp5(_vsp_wsgi_app)\n")
            nA += 1
            continue

        # If it's a plain name (no call), keep as-is but move into _vsp_wsgi_app to avoid clobbering Flask app
        # (rare, but safer than breaking import)
        if "(" not in rhs:
            out.append(f"{indent}_vsp_wsgi_app = {rhs.strip()}\n")
            nA += 1
            continue

        # Otherwise: it's a call or callable construction
        rhs2 = rhs

        # first-arg swap: (application  -> (_vsp_wsgi_app
        rhs2 = re.sub(r'\(\s*application(\s*(?:,|\)))', r'(_vsp_wsgi_app\1', rhs2, flags=re.S)
        rhs2 = re.sub(r'\(\s*app(\s*(?:,|\)))', r'(_vsp_wsgi_app\1', rhs2, flags=re.S)

        # other-arg swap: , application -> , _vsp_wsgi_app
        rhs2 = re.sub(r'([,(]\s*)application(\s*[,)\]])', r'\1_vsp_wsgi_app\2', rhs2)
        rhs2 = re.sub(r'([,(]\s*)app(\s*[,)\]])', r'\1_vsp_wsgi_app\2', rhs2)

        out.append(f"{indent}_vsp_wsgi_app = {rhs2.lstrip()}")
        nA += 1
    return "".join(out), nA

s, nA = rewrite_app_assignments(s)

# 3) Before decorators (@application.after_request), restore Flask app + attach WSGI chain
decor = re.search(r'(?m)^\s*@application\.', s)
restore_block = (
    "\n# VSP_P1_APP_OBJECT_SPLIT_APPLY_V7\n"
    "application = _vsp_flask_app\n"
    "try:\n"
    "    application.wsgi_app = _vsp_wsgi_app\n"
    "except Exception:\n"
    "    pass\n\n"
)
if decor:
    s = s[:decor.start()] + restore_block + s[decor.start():]
else:
    s += restore_block

p.write_text(s, encoding="utf-8")
print(f"[OK] patched: rewrote_app_assignments={nA} wsgi_assign_head={n_w1} wsgi_app_refs={n_w2}")
PY

echo "== sanity: no more application= overwrites in first 120 matches =="
grep -nE '^\s*application\s*=' "$GW" | head -n 120 || true

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
