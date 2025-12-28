#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_recursion_base_wsgi_${TS}"
echo "[BACKUP] ${GW}.bak_recursion_base_wsgi_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_BASE_WSGI_COERCE_V12"
if MARK not in s:
    # insert helper near top (after shebang/comments/encoding/import block-ish)
    lines = s.splitlines(True)
    ins = 0
    for i, line in enumerate(lines[:200]):
        # after initial comments/encoding, insert before first non-comment "def/class" if possible
        if line.startswith("def ") or line.startswith("class "):
            ins = i
            break
        if line.startswith("import ") or line.startswith("from "):
            ins = i+1
    helper = (
        f"\n# {MARK}\n"
        "def _vsp_is_flask_app(obj):\n"
        "    return obj is not None and hasattr(obj, 'after_request') and hasattr(obj, 'route')\n"
        "\n"
        "def _vsp_base_wsgi(obj):\n"
        "    # If someone passed a Flask app object, return its ORIGINAL Flask.wsgi_app bound method,\n"
        "    # not the overwritten instance attribute (prevents recursion).\n"
        "    if _vsp_is_flask_app(obj):\n"
        "        try:\n"
        "            return obj.__class__.wsgi_app.__get__(obj, obj.__class__)\n"
        "        except Exception:\n"
        "            return getattr(obj, 'wsgi_app', obj)\n"
        "    return getattr(obj, 'wsgi_app', obj)\n"
        "\n"
    )
    lines.insert(ins, helper)
    s = "".join(lines)

# rewrite every plain assignment: self.app = <expr>  (single token expr)
# into: self.app = _vsp_base_wsgi(<expr>)
# This fixes the common pattern that causes recursion: middleware keeps Flask app object.
pat = re.compile(r'(?m)^(?P<indent>[ \t]*)self\.app\s*=\s*(?P<rhs>[A-Za-z_][A-Za-z0-9_]*)\s*$')
def repl(m):
    rhs = m.group("rhs")
    if rhs.startswith("_vsp_base_wsgi"):
        return m.group(0)
    return f"{m.group('indent')}self.app = _vsp_base_wsgi({rhs})"
s2, n = pat.subn(repl, s)

p.write_text(s2, encoding="utf-8")
print(f"[OK] rewired self.app assignments: {n}")
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
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,20p'
echo "== error log tail =="
tail -n 120 out_ci/ui_8910.error.log || true
