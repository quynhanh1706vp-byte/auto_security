#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_defaults_v8_${TS}"
echo "[BACKUP] $F.bak_defaults_v8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_DEFAULTS_V8 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# find def run_v1(...)
mdef = re.search(r"(?m)^(?P<ind>\s*)def\s+run_v1\s*\(", t)
if not mdef:
    # sometimes function name is different; fallback: find route decorator for /api/vsp/run_v1 then next def
    mdec = re.search(r"(?m)^@.*(/api/vsp/run_v1|\"/api/vsp/run_v1\"|'\/api\/vsp\/run_v1').*$", t)
    if not mdec:
        raise SystemExit("[ERR] cannot find def run_v1() nor decorator for /api/vsp/run_v1 in run_api/vsp_run_api_v1.py")
    mdef = re.search(r"(?m)^(?P<ind>\s*)def\s+\w+\s*\(", t[mdec.end():])
    if not mdef:
        raise SystemExit("[ERR] cannot find function after /api/vsp/run_v1 decorator")
    def_start = mdec.end() + mdef.start()
    fn_indent = mdef.group("ind")
else:
    def_start = mdef.start()
    fn_indent = mdef.group("ind")

# take a window after def_start to locate request.get_json assignment and variable name
win = t[def_start:def_start+12000]
mjson = re.search(r"(?m)^(?P<ind>\s*)(?P<var>\w+)\s*=\s*request\.get_json\(", win)
if not mjson:
    # accept patterns like: var = (request.get_json(silent=True) or {})
    mjson = re.search(r"(?m)^(?P<ind>\s*)(?P<var>\w+)\s*=\s*\(\s*request\.get_json\(", win)

if not mjson:
    # fallback: inject right after def line
    after_def = re.search(r"(?m)^" + re.escape(fn_indent) + r"def\s+\w+\s*\(.*\)\s*:\s*$", win)
    if not after_def:
        raise SystemExit("[ERR] cannot locate injection point in run_v1")
    inject_pos = def_start + after_def.end()
    ind = fn_indent + "    "
    var = "j"
    injected = f"""
{TAG}
{ind}# Commercial: accept empty payload by applying safe defaults
{ind}try:
{ind}    {var} = {var} if isinstance({var}, dict) else {{}}
{ind}except Exception:
{ind}    {var} = {{}}
{ind}{var}.setdefault("mode","local")
{ind}{var}.setdefault("profile","FULL_EXT")
{ind}{var}.setdefault("target_type","path")
{ind}{var}.setdefault("target","/home/test/Data/SECURITY-10-10-v4")
{ind}# env_overrides must be dict (allowlist enforced elsewhere)
{ind}if "env_overrides" in {var} and not isinstance({var}.get("env_overrides"), dict):
{ind}    {var}.pop("env_overrides", None)
"""
    t2 = t[:inject_pos] + injected + t[inject_pos:]
    p.write_text(t2, encoding="utf-8")
    print("[OK] injected defaults after def (fallback)")
    raise SystemExit(0)

# normal injection: right AFTER the request.get_json(...) line (and keep same indent level)
ind = mjson.group("ind")
var = mjson.group("var")
line_end = win.find("\n", mjson.end())
if line_end < 0:
    raise SystemExit("[ERR] malformed file (no newline after get_json line)")
inject_pos = def_start + line_end + 1

injected = f"""{TAG}
{ind}# Commercial: accept empty payload by applying safe defaults
{ind}try:
{ind}    {var} = {var} if isinstance({var}, dict) else {{}}
{ind}except Exception:
{ind}    {var} = {{}}
{ind}{var}.setdefault("mode","local")
{ind}{var}.setdefault("profile","FULL_EXT")
{ind}{var}.setdefault("target_type","path")
{ind}{var}.setdefault("target","/home/test/Data/SECURITY-10-10-v4")
{ind}# env_overrides must be dict (allowlist enforced elsewhere)
{ind}if "env_overrides" in {var} and not isinstance({var}.get("env_overrides"), dict):
{ind}    {var}.pop("env_overrides", None)
"""

t2 = t[:inject_pos] + injected + t[inject_pos:]
p.write_text(t2, encoding="utf-8")
print(f"[OK] injected defaults in run_v1 using var='{var}'")
PY

python3 -m py_compile run_api/vsp_run_api_v1.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify POST {} to /api/vsp/run_v1 (should be 200 now) =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" \
  -H "Content-Type: application/json" \
  -d '{}' | sed -n '1,200p'
