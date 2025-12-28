#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "== [1] recover vsp_demo_app.py to latest COMPILABLE backup =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_before_recover_${TS}"
echo "[BACKUP] $F.bak_before_recover_${TS}"

# try current first
if python3 -m py_compile "$F" >/dev/null 2>&1; then
  echo "[OK] current file compiles (unexpected). continue patch."
else
  echo "[WARN] current file does NOT compile. searching backups..."
  CANDS="$(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true)"
  if [ -z "$CANDS" ]; then
    echo "[ERR] no backups found: vsp_demo_app.py.bak_*"
    exit 2
  fi

  OK_BAK=""
  for B in $CANDS; do
    cp -f "$B" "$F"
    if python3 -m py_compile "$F" >/dev/null 2>&1; then
      OK_BAK="$B"
      break
    fi
  done

  if [ -z "$OK_BAK" ]; then
    echo "[ERR] no compilable backup found"
    exit 3
  fi
  echo "[OK] restored $F <= $OK_BAK"
fi

echo "== [2] patch run_status_v1 handler: append KICS HB into tail (dynamic indent) =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_STATUS_TAIL_APPEND_KICS_HB_V3 ==="
if TAG in t:
    print("[OK] already patched V3")
    raise SystemExit(0)

# Locate the route decorator containing run_status_v1, regardless of blueprint/app name
# Example: @app.route("/api/vsp/run_status_v1/<rid>") or @bp.route(...)
route_pat = re.compile(
    r"^@[^\n]*route\([^\n]*run_status_v1[^\n]*\)\s*\n(?:^[^\n]*\n)*?^def\s+[A-Za-z_]\w*\([^\)]*\)\s*:\s*\n",
    re.M
)
m = route_pat.search(t)
if not m:
    print("[ERR] cannot locate decorator+def for run_status_v1")
    raise SystemExit(2)

fn_start = m.start()
# function end: next top-level def or next decorator at column 0
m_end = re.search(r"^(?:@|def)\s+", t[m.end():], flags=re.M)
fn_end = (m.end() + m_end.start()) if m_end else len(t)

fn = t[fn_start:fn_end]

# Find first return line that returns jsonify(...) (or has jsonify in it)
rm = re.search(r"^([ \t]+)return\s+.*jsonify\(", fn, flags=re.M)
if not rm:
    print("[ERR] cannot find 'return ... jsonify(' inside run_status_v1 handler")
    raise SystemExit(3)

indent = rm.group(1)
insert_pos = rm.start()

block_lines = [
TAG,
"try:",
"    import os, re as _re",
"    _stage = str(locals().get('stage_name') or locals().get('stage') or '').lower()",
"    _ci = str(locals().get('ci_run_dir') or '')",
"    _resp = locals().get('resp') or locals().get('payload') or locals().get('out') or None",
"    if ('kics' in _stage) and _ci and isinstance(_resp, dict):",
"        _klog = os.path.join(_ci, 'kics', 'kics.log')",
"        if os.path.exists(_klog):",
"            _raw = Path(_klog).read_bytes()[-65536:].decode('utf-8', errors='ignore').replace('\\r', '\\n')",
"            _hb = ''",
"            for _ln in reversed(_raw.splitlines()):",
"                if '][HB]' in _ln and '[KICS_V' in _ln:",
"                    _hb = _ln.strip()",
"                    break",
"            _lines = [x for x in _raw.splitlines() if x.strip()]",
"            _tail = '\\n'.join(_lines[-20:])",
"            if _hb and (_hb not in _tail):",
"                _tail = _hb + '\\n' + _tail",
"            _resp['tail'] = _tail[-4096:]",
"except Exception:",
"    pass",
"# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V3 ===",
""
]

# apply indentation
blk = "\n".join((indent + ln if ln.strip() else ln) for ln in block_lines)

fn2 = fn[:insert_pos] + blk + fn[insert_pos:]
t2 = t[:fn_start] + fn2 + t[fn_end:]

p.write_text(t2, encoding="utf-8")
print("[OK] patched run_status_v1 handler with KICS HB tail (indent=", repr(indent), ")")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [3] restart clean (ensure old is killed) =="
pkill -f "vsp_demo_app.py" || true
nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== [4] verify healthz + show running pid =="
curl -sS http://127.0.0.1:8910/healthz; echo
pgrep -af "vsp_demo_app.py" || true
