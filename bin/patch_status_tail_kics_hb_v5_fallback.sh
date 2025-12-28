#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_tail_kics_hb_v5_${TS}"
echo "[BACKUP] $F.bak_tail_kics_hb_v5_${TS}"

python3 - <<'PY'
import ast, re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# cleanup old attempts (best-effort)
t = re.sub(r"# === VSP_STATUS_TAIL_APPEND_KICS_HB_V[0-9]+ ===.*?# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V[0-9]+ ===\n?", "", t, flags=re.S)
t = re.sub(r"# === VSP_STATUS_TAIL_PREFER_KICS_LOG_V1.*?# === END VSP_STATUS_TAIL_PREFER_KICS_LOG_V1.*?\n?", "", t, flags=re.S)

TAG = "# === VSP_STATUS_TAIL_APPEND_KICS_HB_V5 ==="
if TAG in t:
    print("[OK] already patched V5")
    p.write_text(t, encoding="utf-8")
    raise SystemExit(0)

mod = ast.parse(t)

target = None
for node in ast.walk(mod):
    if isinstance(node, ast.FunctionDef) and node.name == "_fallback_run_status_v1":
        target = node
        break

if not target or not getattr(target, "end_lineno", None):
    print("[ERR] cannot locate function _fallback_run_status_v1 with end_lineno (ast)")
    raise SystemExit(4)

lines = t.splitlines(True)
start = target.lineno - 1
end = target.end_lineno  # slice end (exclusive)
fn_lines = lines[start:end]

# detect base indent from def line
def_line = fn_lines[0]
base_indent = re.match(r"^(\s*)def\s+_fallback_run_status_v1\b", def_line).group(1)

# find last 'return' inside this function
ret_idx = None
ret_indent = None
for i in range(len(fn_lines)-1, 0, -1):
    m = re.match(r"^(\s*)return\b", fn_lines[i])
    if m and len(m.group(1)) > len(base_indent):
        ret_idx = i
        ret_indent = m.group(1)
        break

if ret_idx is None:
    # fallback: insert near end (before last line)
    ret_idx = len(fn_lines)-1
    ret_indent = base_indent + "    "

block = f"""{TAG}
try:
    import os
    # try to pull variables (depends on existing handler)
    _stage = str(locals().get('stage_name') or locals().get('stage') or '').lower()
    _ci = str(locals().get('ci_run_dir') or locals().get('ci_dir') or '')
    _resp = locals().get('resp') or locals().get('payload') or locals().get('out') or locals().get('ret')
    if ('kics' in _stage) and _ci:
        _klog = os.path.join(_ci, 'kics', 'kics.log')
        if os.path.exists(_klog):
            _raw = open(_klog, 'rb').read()[-65536:].decode('utf-8', errors='ignore').replace('\\r','\\n')
            _hb = ''
            for _ln in reversed(_raw.splitlines()):
                if '][HB]' in _ln and '[KICS_V' in _ln:
                    _hb = _ln.strip()
                    break
            _lines = [x for x in _raw.splitlines() if x.strip()]
            _tail = '\\n'.join(_lines[-20:])
            if _hb and (_hb not in _tail):
                _tail = _hb + '\\n' + _tail
            if isinstance(_resp, dict):
                _resp['tail'] = _tail[-4096:]
except Exception:
    pass
# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V5 ===
"""

# apply indentation
blk_lines = []
for ln in block.splitlines(True):
    if ln.strip():
        blk_lines.append(ret_indent + ln)
    else:
        blk_lines.append(ln)

fn_lines2 = fn_lines[:ret_idx] + blk_lines + fn_lines[ret_idx:]
lines2 = lines[:start] + fn_lines2 + lines[end:]
t2 = "".join(lines2)

p.write_text(t2, encoding="utf-8")
print("[OK] patched V5 into _fallback_run_status_v1 at line", target.lineno)
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
