#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need sed

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_alias_v2_${TS}"
echo "[BACKUP] ${W}.bak_alias_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_ALIAS_REPORTS_GATE_V2"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

# 1) Find handler function def: def vsp_run_file_allow...(
mdef = re.search(r"(?m)^def\s+(vsp_run_file_allow\w*)\s*\(", s)
if not mdef:
    # fallback: find route decorator containing run_file_allow then next def
    mroute = re.search(r"(?m)^[^\n]*run_file_allow[^\n]*\n(?=def\s+)", s)
    if not mroute:
        raise SystemExit("[ERR] cannot find run_file_allow handler (def vsp_run_file_allow*)")
    start = mroute.end()
    mdef2 = re.search(r"(?m)^def\s+(\w+)\s*\(", s[start:])
    if not mdef2:
        raise SystemExit("[ERR] found route but cannot find def after it")
    func_name = mdef2.group(1)
    def_pos = start + mdef2.start()
else:
    func_name = mdef.group(1)
    def_pos = mdef.start()

# 2) Extract function block: from def_pos to next top-level def
rest = s[def_pos:]
mnext = re.search(r"(?m)^def\s+\w+\s*\(", rest[1:])  # skip current char to avoid matching itself
end_pos = def_pos + (mnext.start(0)+1 if mnext else len(rest))
block = s[def_pos:end_pos]

lines = block.splitlines(True)

# 3) Find the line that retrieves 'path' (robust patterns)
get_line_i = None
lhs_var = None

get_patterns = [
    re.compile(r"^\s*(\w+)\s*=\s*.*\b(get|getlist|pop)\s*\(.*['\"]path['\"]", re.IGNORECASE),
    re.compile(r"^\s*(\w+)\s*=\s*.*request\.(args|values|form|json|headers)\b.*['\"]path['\"]", re.IGNORECASE),
    re.compile(r"^\s*(\w+)\s*=\s*.*['\"]path['\"].*\)", re.IGNORECASE),
]

for i, ln in enumerate(lines):
    # stop if we hit another nested def at col 0 within block (rare)
    if re.match(r"^def\s+\w+\s*\(", ln):
        break
    for pat in get_patterns:
        mm = pat.search(ln)
        if mm:
            get_line_i = i
            lhs_var = mm.group(1)
            break
    if get_line_i is not None:
        break

# fallback: look for request.* and 'path' anywhere, then try infer lhs from assignment
if get_line_i is None:
    for i, ln in enumerate(lines):
        if "path" in ln and "request." in ln:
            m = re.match(r"^\s*(\w+)\s*=", ln)
            if m:
                get_line_i = i
                lhs_var = m.group(1)
                break

# fallback2: place just before returning "not allowed" inside this block and assume var 'path'
if get_line_i is None:
    for i, ln in enumerate(lines):
        if "not allowed" in ln:
            get_line_i = max(0, i-1)
            lhs_var = "path"
            break

if get_line_i is None or not lhs_var:
    raise SystemExit(f"[ERR] cannot locate where handler reads path inside {func_name}()")

# Determine indentation based on that line
indent = re.match(r"^(\s*)", lines[get_line_i]).group(1)
inj = f"""{indent}# ===================== {MARK} =====================
{indent}# Alias reports/run_gate*.json -> root gate*.json to avoid 403 when artifacts are stored at root.
{indent}try:
{indent}  _p0 = ({lhs_var} or "").replace("\\\\","/").lstrip("/")
{indent}  if _p0 in ("reports/run_gate_summary.json", "reports/run_gate.json"):
{indent}    {lhs_var} = _p0.split("/", 1)[1]
{indent}except Exception:
{indent}  pass
{indent}# ===================== /{MARK} =====================
"""

# Insert after the get_line_i line (after retrieving path)
insert_at = get_line_i + 1
lines2 = lines[:insert_at] + [inj] + lines[insert_at:]
block2 = "".join(lines2)

# Replace in full text
s2 = s[:def_pos] + block2 + s[end_pos:]
p.write_text(s2, encoding="utf-8")
print(f"[OK] injected alias into {func_name}(), var={lhs_var}, line={get_line_i+1}")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.6
echo "[OK] restarted (or attempted)"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_RUN_20251219_092640}"

echo "== reports gate summary (expect 200) =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | sed -n '1,15p'

echo "== reports gate (expect 200) =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate.json" | sed -n '1,15p'
