#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_gate_panel_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_asyncfix_${TS}" && echo "[BACKUP] $F.bak_asyncfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_gate_panel_v1.js")
lines = p.read_text(encoding="utf-8").splitlines(True)

# find the await line we inserted
idx = None
for i,l in enumerate(lines):
    if "await fetch(u2" in l or "await fetch(u2," in l:
        idx = i
        break
if idx is None:
    raise SystemExit("[ERR] cannot find 'await fetch(u2' in gate panel (nothing to fix)")

def add_async_to_line(l: str) -> str|None:
    # 1) function foo(...) {  -> async function foo(...) {
    m = re.match(r'^(\s*)function(\s+\w+\s*\()', l)
    if m and "async function" not in l:
        return re.sub(r'^(\s*)function(\s+\w+\s*\()', r'\1async function\2', l, count=1)

    # 2) function(...) {  -> async function(...) {
    m = re.match(r'^(\s*)function(\s*\()', l)
    if m and "async function" not in l:
        return re.sub(r'^(\s*)function(\s*\()', r'\1async function\2', l, count=1)

    # 3) const x = function(...) { -> const x = async function(...) {
    if re.search(r'=\s*function\s*\(', l) and "async function" not in l:
        return re.sub(r'=\s*function\s*\(', r'= async function(', l, count=1)

    # 4) const x = (...) => {  -> const x = async (...) => {
    if "=>" in l and "async" not in l:
        # only touch assignment arrows (avoid comparisons)
        if re.search(r'=\s*(\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>\s*{', l):
            return re.sub(r'=\s*(\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>',
                          r'= async \1 =>', l, count=1)
    return None

patched = False
# search backwards for nearest enclosing function/arrow
for j in range(idx, max(-1, idx-200), -1):
    nl = add_async_to_line(lines[j])
    if nl is not None and nl != lines[j]:
        lines[j] = nl
        patched = True
        break

# fallback: make top-level IIFE async if needed
if not patched:
    for j in range(0, min(len(lines), 80)):
        if "(function" in lines[j] and "async function" not in lines[j]:
            lines[j] = lines[j].replace("(function", "(async function", 1)
            patched = True
            break

if not patched:
    raise SystemExit("[ERR] could not locate a function to mark async near await-line")

p.write_text("".join(lines), encoding="utf-8")
print("[OK] marked nearest function as async to allow await")
PY

# must parse OK BEFORE restart
node --check "$F" >/dev/null && echo "[OK] node --check OK: $F"

# restart 8910
PID_FILE="out_ci/ui_8910.pid"
PID="$(cat "$PID_FILE" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.6

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PID_FILE" \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.nohup.log 2>&1 &

sleep 1.0
curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null && echo "[OK] UI up: /vsp4"
echo "[DONE] Hard refresh Ctrl+Shift+R, then re-check CI/CD Gate + console"
