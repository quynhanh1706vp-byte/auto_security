#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_return_use_out_${TS}"
echo "[BACKUP] $F.bak_fix_return_use_out_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# locate def _fallback_run_status_v1
def_i = None
def_ind = ""
for i,s in enumerate(lines):
    m = re.match(r"^([ \t]*)def\s+_fallback_run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", s)
    if m:
        def_i = i
        def_ind = m.group(1)
        break
if def_i is None:
    raise SystemExit("[ERR] cannot find def _fallback_run_status_v1(req_id)")

# function end = next non-empty line with indent <= def_ind (or EOF)
end = len(lines)
def_len = len(def_ind)
for j in range(def_i+1, len(lines)):
    s = lines[j]
    if not s.strip():
        continue
    ind = re.match(r"^([ \t]*)", s).group(1)
    if len(ind) <= def_len and not s.lstrip().startswith(("#", "@")):
        end = j
        break

# patch LAST return jsonify(...) inside function range
ret_i = None
for j in range(end-1, def_i, -1):
    if "return" in lines[j] and "jsonify" in lines[j]:
        ret_i = j
        break
if ret_i is None:
    raise SystemExit("[ERR] cannot find return jsonify(...) in _fallback_run_status_v1")

ind_ret = re.match(r"^([ \t]*)", lines[ret_i]).group(1)

# if already using locals().get('_out'), do nothing
if "locals().get('_out')" in lines[ret_i] or "jsonify(_out)" in lines[ret_i]:
    print("[OK] already returns _out (or locals().get('_out'))")
else:
    lines[ret_i] = (
        ind_ret
        + "return jsonify( (locals().get('_out') if isinstance(locals().get('_out'), dict) "
        + "else _vsp_contractize(_VSP_FALLBACK_REQ[req_id])) ), 200\n"
    )
    print(f"[OK] patched final return line={ret_i+1} to prefer _out")

p.write_text("".join(lines), encoding="utf-8")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== restart 8910 =="
PIDS="$(lsof -ti :8910 2>/dev/null || true)"
if [ -n "${PIDS}" ]; then
  echo "[KILL] 8910 pids: ${PIDS}"
  kill -9 ${PIDS} || true
fi
nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo
echo "[OK] done"
