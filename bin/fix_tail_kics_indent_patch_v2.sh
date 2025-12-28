#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_tail_kics_v2_${TS}"
echo "[BACKUP] $F.bak_fix_tail_kics_v2_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# 1) Remove any previously injected SAFE block (even partial)
t2 = re.sub(
    r"\n?[ \t]*# === VSP_STATUS_TAIL_PREFER_KICS_LOG_V1_SAFE ===[\s\S]*?# === END VSP_STATUS_TAIL_PREFER_KICS_LOG_V1_SAFE ===\n?",
    "\n",
    t,
    flags=re.M
)
if t2 != t:
    print("[OK] removed old SAFE block")
t = t2

# 2) Find run_status_v1 handler
m = re.search(r"^def\s+([A-Za-z_]\w*run_status_v1\w*)\s*\(", t, flags=re.M)
if not m:
    print("[ERR] cannot find function name containing run_status_v1")
    raise SystemExit(2)

fn_start = m.start()
fn_end = t.find("\ndef ", fn_start + 1)
if fn_end < 0:
    fn_end = len(t)

fn_body = t[fn_start:fn_end]

# 3) Find first "return jsonify" inside that function
rm = re.search(r"^([ \t]+)return\s+jsonify\b", fn_body, flags=re.M)
if not rm:
    print("[ERR] cannot find 'return jsonify' inside run_status_v1 handler")
    raise SystemExit(3)

indent = rm.group(1)
insert_pos_in_fn = rm.start()

# 4) Build snippet with correct indentation (prefix every line)
base = [
"# === VSP_STATUS_TAIL_PREFER_KICS_LOG_V1_SAFE ===",
"try:",
"    import os",
"    _cand = None",
"    for _v in locals().values():",
"        if isinstance(_v, dict) and ('ci_run_dir' in _v) and (('stage_name' in _v) or ('stage' in _v)):",
"            _cand = _v",
"            break",
"    if _cand:",
"        _sn = str(_cand.get('stage_name') or _cand.get('stage') or '').lower()",
"        _ci = str(_cand.get('ci_run_dir') or '')",
"        if ('kics' in _sn) and _ci:",
"            _klog = os.path.join(_ci, 'kics', 'kics.log')",
"            if os.path.exists(_klog):",
"                with open(_klog, 'rb') as _f:",
"                    _b = _f.read()[-4096:]",
"                _cand['tail'] = _b.decode('utf-8', errors='ignore')",
"except Exception:",
"    pass",
"# === END VSP_STATUS_TAIL_PREFER_KICS_LOG_V1_SAFE ===",
""
]
snip = "\n".join((indent + line if line.strip() else line) for line in base)

fn_body_new = fn_body[:insert_pos_in_fn] + snip + fn_body[insert_pos_in_fn:]
t_new = t[:fn_start] + fn_body_new + t[fn_end:]

p.write_text(t_new, encoding="utf-8")
print("[OK] inserted SAFE tail snippet with dynamic indent =", repr(indent))
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
