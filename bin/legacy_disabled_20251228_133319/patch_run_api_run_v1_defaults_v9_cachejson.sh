#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_defaults_v9_${TS}"
echo "[BACKUP] $F.bak_defaults_v9_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# 1) remove old V8 block if exists
t, n_rm = re.subn(
    r"(?ms)^\s*# === VSP_RUN_V1_DEFAULTS_V8 ===.*?(?=^\S|\Z)",
    "",
    t
)

TAG = "# === VSP_RUN_V1_DEFAULTS_V9_CACHEJSON ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# 2) locate run_v1 function area
mdef = re.search(r"(?m)^(?P<ind>\s*)def\s+run_v1\s*\(", t)
if not mdef:
    # fallback: find decorator for /api/vsp/run_v1 then next def
    mdec = re.search(r"(?m)^@.*(/api/vsp/run_v1|\"/api/vsp/run_v1\"|'\/api\/vsp\/run_v1').*$", t)
    if not mdec:
        raise SystemExit("[ERR] cannot find def run_v1() nor decorator for /api/vsp/run_v1 in run_api/vsp_run_api_v1.py")
    mdef2 = re.search(r"(?m)^(?P<ind>\s*)def\s+\w+\s*\(", t[mdec.end():])
    if not mdef2:
        raise SystemExit("[ERR] cannot find function after /api/vsp/run_v1 decorator")
    def_start = mdec.end() + mdef2.start()
else:
    def_start = mdef.start()

# window from run_v1 start
win = t[def_start:def_start+15000]

# 3) find first assignment from request.get_json(...) inside that window
mjson = re.search(r"(?m)^(?P<ind>\s*)(?P<var>\w+)\s*=\s*\(?\s*request\.get_json\(", win)
if not mjson:
    raise SystemExit("[ERR] cannot locate '<var> = request.get_json(...)' inside run_v1")

ind = mjson.group("ind")
var = mjson.group("var")

# insert AFTER that get_json line (end of line)
line_end = win.find("\n", mjson.end())
if line_end < 0:
    raise SystemExit("[ERR] malformed file (no newline after get_json line)")
inject_pos = def_start + line_end + 1

block = f"""{TAG}
{ind}# Commercial: accept empty payload by applying safe defaults (and freeze request JSON cache)
{ind}try:
{ind}    {var} = {var} if isinstance({var}, dict) else {{}}
{ind}except Exception:
{ind}    {var} = {{}}
{ind}{var}.setdefault("mode","local")
{ind}{var}.setdefault("profile","FULL_EXT")
{ind}{var}.setdefault("target_type","path")
{ind}{var}.setdefault("target","/home/test/Data/SECURITY-10-10-v4")
{ind}# env_overrides must be dict
{ind}if "env_overrides" in {var} and not isinstance({var}.get("env_overrides"), dict):
{ind}    {var}.pop("env_overrides", None)
{ind}# IMPORTANT: subsequent request.get_json()/request.json must see the same defaults
{ind}try:
{ind}    request._cached_json = {{False: {var}, True: {var}}}
{ind}except Exception:
{ind}    pass
"""

t2 = t[:inject_pos] + block + t[inject_pos:]
p.write_text(t2, encoding="utf-8")
print(f"[OK] patched run_v1 defaults+cache using var='{var}', removed_old_blocks={n_rm}")
PY

python3 -m py_compile run_api/vsp_run_api_v1.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify POST {} to /api/vsp/run_v1 (must be 200) =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" \
  -H "Content-Type: application/json" \
  -d '{}' | sed -n '1,200p'
