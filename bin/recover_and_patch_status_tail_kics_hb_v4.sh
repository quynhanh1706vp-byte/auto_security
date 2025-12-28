#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "== [1] recover vsp_demo_app.py to latest COMPILABLE backup =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_before_recover_${TS}"
echo "[BACKUP] $F.bak_before_recover_${TS}"

if python3 -m py_compile "$F" >/dev/null 2>&1; then
  echo "[OK] current file compiles"
else
  echo "[WARN] current file does NOT compile. searching backups..."
  CANDS="$(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true)"
  [ -n "$CANDS" ] || { echo "[ERR] no backups found: vsp_demo_app.py.bak_*"; exit 2; }

  OK_BAK=""
  for B in $CANDS; do
    cp -f "$B" "$F"
    if python3 -m py_compile "$F" >/dev/null 2>&1; then
      OK_BAK="$B"
      break
    fi
  done

  [ -n "$OK_BAK" ] || { echo "[ERR] no compilable backup found"; exit 3; }
  echo "[OK] restored $F <= $OK_BAK"
fi

echo "== [2] patch run_status_v1 handler BY ROUTE STRING (/api/vsp/run_status_v1) =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# 1) remove old/failed blocks (best-effort)
t = re.sub(r"# === VSP_STATUS_TAIL_.*?===\n.*?# === END VSP_STATUS_TAIL_.*?===\n", "", t, flags=re.S)
t = re.sub(r"# === VSP_STATUS_TAIL_APPEND_KICS_HB_V3 ===\n.*?# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V3 ===\n", "", t, flags=re.S)

TAG = "# === VSP_STATUS_TAIL_APPEND_KICS_HB_V4 ==="
if TAG in t:
    print("[OK] already patched V4")
    raise SystemExit(0)

# 2) find the function by locating the route string (handles multi-line decorators)
m_route = re.search(r"/api/vsp/run_status_v1", t)
if not m_route:
    print("[ERR] cannot find route string '/api/vsp/run_status_v1' in file")
    raise SystemExit(4)

# next def after route occurrence
m_def = re.search(r"^def\s+[A-Za-z_]\w*\s*\([^\)]*\)\s*:\s*$", t[m_route.start():], flags=re.M)
if not m_def:
    print("[ERR] cannot find 'def ...:' after route string")
    raise SystemExit(5)

fn_start = m_route.start() + m_def.start()

# function end: next top-level decorator/def
m_end = re.search(r"^(?:@|def)\s+", t[fn_start+1:], flags=re.M)
fn_end = (fn_start+1 + m_end.start()) if m_end else len(t)

fn = t[fn_start:fn_end]

# find return jsonify line (indent anchor)
rm = re.search(r"^([ \t]+)return\s+.*jsonify\(", fn, flags=re.M)
if not rm:
    print("[ERR] cannot find 'return ... jsonify(' in located handler")
    raise SystemExit(6)

indent = rm.group(1)
insert_pos = rm.start()

block = [
TAG,
"try:",
"    import os",
"    _stage = str(locals().get('stage_name') or locals().get('stage') or '').lower()",
"    _ci = str(locals().get('ci_run_dir') or '')",
"    if ('kics' in _stage) and _ci:",
"        _klog = os.path.join(_ci, 'kics', 'kics.log')",
"        if os.path.exists(_klog):",
"            _raw = open(_klog, 'rb').read()[-65536:].decode('utf-8', errors='ignore').replace('\\r','\\n')",
"            _hb = ''",
"            for _ln in reversed(_raw.splitlines()):",
"                if '][HB]' in _ln and '[KICS_V' in _ln:",
"                    _hb = _ln.strip()",
"                    break",
"            _lines = [x for x in _raw.splitlines() if x.strip()]",
"            _tail = '\\n'.join(_lines[-20:])",
"            if _hb and (_hb not in _tail):",
"                _tail = _hb + '\\n' + _tail",
"            # try to write back into response dict if present; else set local var 'tail' if exists",
"            _resp = locals().get('resp') or locals().get('payload') or locals().get('out')",
"            if isinstance(_resp, dict):",
"                _resp['tail'] = _tail[-4096:]",
"            elif 'tail' in locals():",
"                tail = _tail[-4096:]",
"except Exception:",
"    pass",
"# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V4 ===",
""
]

blk = "\n".join((indent + ln if ln.strip() else ln) for ln in block)
fn2 = fn[:insert_pos] + blk + fn[insert_pos:]
t2 = t[:fn_start] + fn2 + t[fn_end:]

p.write_text(t2, encoding="utf-8")
print("[OK] patched V4 (indent=", repr(indent), ")")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [3] hard restart port 8910 (kill anything listening) =="
# kill python/gunicorn holding 8910
PIDS="$(lsof -ti :8910 2>/dev/null || true)"
if [ -n "${PIDS}" ]; then
  echo "[KILL] 8910 pids: ${PIDS}"
  kill -9 ${PIDS} || true
fi

nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== [4] verify =="
curl -sS http://127.0.0.1:8910/healthz; echo
pgrep -af "vsp_demo_app.py" || true
