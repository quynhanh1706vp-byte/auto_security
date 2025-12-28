#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl; need grep

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_forcewrap_multiline_keepflask_${TS}"
echo "[BACKUP] ${GW}.bak_forcewrap_multiline_keepflask_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_FORCEWRAP_MULTILINE_KEEPFLASK_V4"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

orig = s

# (A) Rewrite ANY: application = _ForceWrapXxx(
#     ... )   (even multiline)
# -> application.wsgi_app = _ForceWrapXxx(
#
# This stops "application" from becoming middleware.
s, nA = re.subn(
    r'(?m)^(?P<indent>[ \t]*)application\s*=\s*(?P<mw>_ForceWrap[A-Za-z0-9_]+)\s*\(',
    r'\g<indent>application.wsgi_app = \g<mw>(',
    s
)

# (B) Inside those _ForceWrap calls, ensure first arg is application.wsgi_app
# Replace "_ForceWrapXxx( application" -> "_ForceWrapXxx( application.wsgi_app"
# across newlines/spaces.
s, nB = re.subn(
    r'(_ForceWrap[A-Za-z0-9_]+\s*\(\s*)application(\s*(?:,|\)))',
    r'\1application.wsgi_app\2',
    s,
    flags=re.S
)

# Add marker near first imports (or top)
lines = s.splitlines(True)
ins = 0
for i, line in enumerate(lines[:120]):
    if line.startswith("import ") or line.startswith("from "):
        ins = i
        break
lines.insert(ins, f"# {MARK}\n")
s = "".join(lines)

p.write_text(s, encoding="utf-8")
print(f"[OK] patch applied: nA={nA} nB={nB}")
PY

echo "== quick grep (forcewrap + after_request) =="
grep -n "_ForceWrapReportsRunFileMW" -n "$GW" || true
grep -n "application[[:space:]]*=" -n "$GW" | head -n 40 || true
grep -n "@application.after_request" -n "$GW" || true

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

sleep 1.0

echo "== ss :8910 =="
ss -ltnp | grep ':8910' || true

echo "== import check (must not crash) =="
python3 - <<'PY'
import wsgi_vsp_ui_gateway as m
print("[OK] imported")
print("type(application) =", type(m.application))
print("has after_request =", hasattr(m.application, "after_request"))
PY

echo "== smoke (root + runs) =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,12p'
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 220; echo

echo "== boot log tail =="
tail -n 80 out_ci/ui_8910.boot.log || true
