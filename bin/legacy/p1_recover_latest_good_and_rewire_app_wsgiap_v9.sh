#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl; need ls

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

echo "== find newest backup that compiles =="
GOOD=""
for f in $(ls -1t "${GW}.bak_"* 2>/dev/null || true); do
  if python3 -m py_compile "$f" >/dev/null 2>&1; then
    GOOD="$f"
    break
  fi
done

if [ -z "$GOOD" ]; then
  echo "[ERR] no backup compiles. list backups:"
  ls -1t "${GW}.bak_"* 2>/dev/null | head -n 30 || true
  exit 3
fi

echo "[OK] using backup: $GOOD"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GOOD" "$GW"
cp -f "$GW" "${GW}.bak_before_rewire_v9_${TS}"
echo "[BACKUP] ${GW}.bak_before_rewire_v9_${TS}"

echo "== rewire application=... to application.wsgi_app=... (safe) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

def is_already_ok(line: str) -> bool:
    return "application.wsgi_app" in line or "_vsp_wsgi_app" in line

# Single-line: application = Foo(application, ...)
pat1 = re.compile(r'^(\s*)application\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\(\s*(application|app)\s*(.*)\)\s*$')

# Multi-line start: application = Foo(
pat_ml_start = re.compile(r'^(\s*)application\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*(.*)$')

out = []
i = 0
rewired = 0

while i < len(s):
    line = s[i]

    # Special-case: application = _vsp_force_default_to_vsp5
    if re.match(r'^\s*application\s*=\s*_vsp_force_default_to_vsp5\s*$', line) and not is_already_ok(line):
        indent = re.match(r'^(\s*)', line).group(1)
        out.append(f"{indent}application.wsgi_app = _vsp_force_default_to_vsp5(application.wsgi_app)\n")
        rewired += 1
        i += 1
        continue

    m1 = pat1.match(line)
    if m1 and not is_already_ok(line):
        indent, fn, _arg0, rest = m1.group(1), m1.group(2), m1.group(3), m1.group(4)
        out.append(f"{indent}application.wsgi_app = {fn}(application.wsgi_app{rest})\n")
        rewired += 1
        i += 1
        continue

    m2 = pat_ml_start.match(line)
    if m2 and not is_already_ok(line):
        indent, fn, tail = m2.group(1), m2.group(2), m2.group(3)
        # collect until parentheses balance
        block = [line]
        depth = line.count("(") - line.count(")")
        j = i + 1
        while j < len(s) and depth > 0:
            block.append(s[j])
            depth += s[j].count("(") - s[j].count(")")
            j += 1

        block_text = "".join(block)

        # rewrite head "application = Fn(" -> "application.wsgi_app = Fn("
        block_text = re.sub(r'(?m)^(\s*)application\s*=\s*' + re.escape(fn) + r'\s*\(',
                            r'\1application.wsgi_app = ' + fn + '(',
                            block_text, count=1)

        # rewrite first arg: (application or (app -> (application.wsgi_app
        block_text = re.sub(r'(' + re.escape(fn) + r'\s*\(\s*)(application|app)(\s*(?:,|\)))',
                            r'\1application.wsgi_app\3', block_text, count=1)

        out.append(block_text)
        rewired += 1
        i = j
        continue

    out.append(line)
    i += 1

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] rewired blocks: {rewired}")
PY

echo "== py_compile after rewire =="
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
