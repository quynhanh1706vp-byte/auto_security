#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_forcewrap_all_keepflask_${TS}"
echo "[BACKUP] ${GW}.bak_forcewrap_all_keepflask_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P1_FORCEWRAP_ALL_KEEPFLASK_V3"

if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Patch any: application = _ForceWrapXxx(application, ...)
# into : application.wsgi_app = _ForceWrapXxx(application.wsgi_app, ...)
#
# Guard: don't touch if already wrapping application.wsgi_app.
pat = re.compile(
    r'^(?P<indent>[ \t]*)application[ \t]*=[ \t]*(?P<mw>_ForceWrap[A-Za-z0-9_]+)[ \t]*\([ \t]*application(?P<rest>[^\)]*)\)[ \t]*$',
    re.M
)

def repl(m):
    indent = m.group("indent")
    mw = m.group("mw")
    rest = m.group("rest") or ""
    # keep existing extra args (", ...") exactly
    return f"{indent}application.wsgi_app = {mw}(application.wsgi_app{rest})"

lines_before = s.count("\n")
n = 0

def already_ok(line: str) -> bool:
    return "application.wsgi_app" in line and "_ForceWrap" in line and " = " in line

out_lines = []
for line in s.splitlines():
    if already_ok(line):
        out_lines.append(line)
        continue
    new_line, k = pat.subn(repl, line)
    if k:
        n += k
        out_lines.append(new_line)
    else:
        out_lines.append(line)

s2 = "\n".join(out_lines) + "\n"

# Add marker near top (after shebang/comments if any)
insert_at = 0
for i, line in enumerate(s2.splitlines(True)[:80]):
    if line.startswith("import ") or line.startswith("from "):
        insert_at = i
        break
parts = s2.splitlines(True)
parts.insert(insert_at, f"# {MARK}\n")
s2 = "".join(parts)

p.write_text(s2, encoding="utf-8")
print(f"[OK] rewired application=_ForceWrap* lines -> application.wsgi_app=... : {n}")
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

echo "== start gunicorn :8910 =="
: > out_ci/ui_8910.boot.log || true
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

sleep 0.9
echo "== ss :8910 =="
ss -ltnp | grep ':8910' || true

echo "== import check (must not crash) =="
python3 - <<'PY'
import wsgi_vsp_ui_gateway as m
print("[OK] imported, type(application)=", type(m.application))
print("[OK] has after_request=", hasattr(m.application, "after_request"))
PY

echo "== smoke (root + runs) =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,12p'
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 200; echo
echo "== boot log tail =="
tail -n 60 out_ci/ui_8910.boot.log || true
