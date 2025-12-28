#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_fix_gitleaks_before_return_${TS}"
echo "[BACKUP] $APP.bak_fix_gitleaks_before_return_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_STATUS_V2_ADD_GITLEAKS_FIELDS_V2_BEFORE_RETURN ==="

# If already inserted, skip
if TAG in t:
    print("[OK] tag exists, skip")
    raise SystemExit(0)

# Find a function that is run_status_v2 handler
# Accept def name contains run_status_v2
mdef = re.search(r"(?m)^(?P<ind>\s*)def\s+(?P<name>\w*run_status_v2\w*)\s*\(", t)
if not mdef:
    # fallback: route decorator contains run_status_v2
    # find nearest subsequent def
    mroute = re.search(r"(?m)run_status_v2", t)
    if not mroute:
        raise SystemExit("[ERR] cannot find run_status_v2 in vsp_demo_app.py")
    # find next def after route mention
    mdef = re.search(r"(?m)^\s*def\s+\w+\s*\(", t[mroute.start():])
    if not mdef:
        raise SystemExit("[ERR] cannot find def after run_status_v2 mention")
    # adjust index
    start = mroute.start() + mdef.start()
    mdef = re.match(r"(?m)^(?P<ind>\s*)def\s+(?P<name>\w+)\s*\(", t[start:])
    if not mdef:
        raise SystemExit("[ERR] failed parsing def after run_status_v2 mention")
    def_start = start
    def_ind = mdef.group("ind")
else:
    def_start = mdef.start()
    def_ind = mdef.group("ind")

# Determine function end as next def with same or less indent at top-level-ish
# We'll scan from def_start onwards
rest = t[def_start:]
lines = rest.splitlines(True)

base_indent = len(def_ind)
func_end_off = len(rest)

# locate next def at indent <= base_indent (excluding first line)
acc = 0
for i, line in enumerate(lines[1:], start=1):
    acc += len(lines[i-1])
    mnext = re.match(r"^(?P<ind>\s*)def\s+\w+\s*\(", line)
    if mnext and len(mnext.group("ind")) <= base_indent:
        func_end_off = acc
        break

func_text = rest[:func_end_off]

# Find last return inside this function (prefer "return" lines, take the last)
returns = list(re.finditer(r"(?m)^(?P<ind>\s*)return\b.*$", func_text))
if not returns:
    raise SystemExit("[ERR] cannot find any return inside run_status_v2 handler")
mret = returns[-1]
ret_ind = mret.group("ind")

# Insert right before that return line
insert_pos = def_start + mret.start()

inject = "\n".join([
    f"{ret_ind}{TAG}",
    f"{ret_ind}try:",
    f"{ret_ind}  import os, json",
    f"{ret_ind}  _gl_paths = [",
    f"{ret_ind}    os.path.join(ci_run_dir,'gitleaks','gitleaks_summary.json'),",
    f"{ret_ind}    os.path.join(ci_run_dir,'gitleaks_summary.json'),",
    f"{ret_ind}  ]",
    f"{ret_ind}  gitleaks_summary = None",
    f"{ret_ind}  for _p in _gl_paths:",
    f"{ret_ind}    if os.path.exists(_p):",
    f"{ret_ind}      with open(_p, 'r', encoding='utf-8', errors='ignore') as _f:",
    f"{ret_ind}        gitleaks_summary = json.load(_f)",
    f"{ret_ind}      break",
    f"{ret_ind}  if isinstance(gitleaks_summary, dict):",
    f"{ret_ind}    # status dict should exist in this scope",
    f"{ret_ind}    status['gitleaks_verdict'] = gitleaks_summary.get('verdict')",
    f"{ret_ind}    status['gitleaks_total']   = gitleaks_summary.get('total')",
    f"{ret_ind}    status['gitleaks_counts']  = gitleaks_summary.get('counts')",
    f"{ret_ind}    status['has_gitleaks']     = True",
    f"{ret_ind}except Exception:",
    f"{ret_ind}  pass",
    ""
])

t2 = t[:insert_pos] + inject + t[insert_pos:]
p.write_text(t2, encoding="utf-8")
print("[OK] inserted gitleaks injector before last return with indent =", repr(ret_ind))
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"
echo "DONE"
