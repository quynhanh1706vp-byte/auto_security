#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_sevfix_v2_${TS}"
echo "[OK] backup: ${APP}.bak_sevfix_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Find route decorator for run_gate_summary_v1
pat = r"""(?s)(@app\.(?:get|route)\(\s*['"]\/api\/vsp\/run_gate_summary_v1['"][^)]*\)\s*(?:\n@.*\n)*)\s*(def\s+[A-Za-z_]\w*\s*\([^)]*\)\s*:\s*\n)"""
m = re.search(pat, s)
if not m:
    # some code uses blueprint: vsp.route(...)
    pat2 = r"""(?s)(@[\w\.]+\.(?:get|route)\(\s*['"]\/api\/vsp\/run_gate_summary_v1['"][^)]*\)\s*(?:\n@.*\n)*)\s*(def\s+[A-Za-z_]\w*\s*\([^)]*\)\s*:\s*\n)"""
    m = re.search(pat2, s)
if not m:
    print("[ERR] cannot find route decorator for /api/vsp/run_gate_summary_v1")
    sys.exit(2)

start_def = m.start(2)
# Find function body end: next "def " at column 0 OR next decorator at column 0
after = s[start_def:]
m_end = re.search(r"(?m)^(?:@|\s*def\s)\b", after.splitlines(True)[1] if False else after)  # placeholder

# robust end: scan from line after def
lines = s.splitlines(True)
# locate line index of def line
def_line_no = s[:start_def].count("\n")
i = def_line_no
# determine base indent inside function (next non-empty line)
body_indent = None
j = i+1
while j < len(lines):
    ln = lines[j]
    if ln.strip() == "":
        j += 1
        continue
    m_indent = re.match(r"^(\s+)", ln)
    body_indent = m_indent.group(1) if m_indent else "    "
    break
if body_indent is None:
    body_indent = "    "

# find function end by walking forward until we hit a top-level def/decorator with no indent
k = i+1
while k < len(lines):
    ln = lines[k]
    if re.match(r"^(def\s+|@)", ln):  # top-level
        break
    k += 1

func_block = "".join(lines[i:k])

if "VSP_SEV_NOTNULL_V2" in func_block:
    print("[OK] already patched V2")
    sys.exit(0)

# Inject before the LAST 'return' at body indentation
ret_matches = list(re.finditer(rf"(?m)^\s*return\b", func_block))
inject_at = ret_matches[-1].start() if ret_matches else len(func_block)

inject = f"""{body_indent}# VSP_SEV_NOTNULL_V2: ensure sev is dict (6-level) so UI never hangs
{body_indent}try:
{body_indent}    try:
{body_indent}        _sev = sev  # may NameError
{body_indent}    except NameError:
{body_indent}        _sev = None
{body_indent}    # normalize
{body_indent}    if not isinstance(_sev, dict):
{body_indent}        _sev = {{}}
{body_indent}    for _k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
{body_indent}        _sev.setdefault(_k, 0)
{body_indent}    # write back to sev var if exists / create it
{body_indent}    sev = _sev
{body_indent}    # also push into common payload dicts if they exist
{body_indent}    for _nm in ("j","data","out","resp","payload","res"):
{body_indent}        _v = locals().get(_nm)
{body_indent}        if isinstance(_v, dict):
{body_indent}            _v["sev"] = _v.get("sev") if isinstance(_v.get("sev"), dict) else _sev
{body_indent}except Exception:
{body_indent}    pass

"""

func_block2 = func_block[:inject_at] + inject + func_block[inject_at:]
# Replace in full file
s2 = "".join(lines[:i]) + func_block2 + "".join(lines[k:])
p.write_text(s2, encoding="utf-8")
print("[OK] patched VSP_SEV_NOTNULL_V2")
PY

python3 -m py_compile vsp_demo_app.py

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.4
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
else
  echo "[WARN] no systemctl; restart manually"
fi

# Quick verify with rid_latest
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"
curl -fsS "$BASE/api/vsp/run_gate_summary_v1?rid=$RID" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); sev=j.get("sev"); print("ok=",j.get("ok"),"sev_type=",type(sev).__name__,"keys=",(sorted(sev.keys()) if isinstance(sev,dict) else None))'
