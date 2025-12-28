#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fixstatus_kics_v4_${TS}"
echo "[BACKUP] $F.bak_fixstatus_kics_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_FIX_STATUS_V16_INJECT_KICS_SUMMARY_V4 ==="
if TAG in t:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# pick latest guess func name (you already have _vsp_guess_ci_run_dir_from_rid_v33)
guess_names = re.findall(r'(?m)^\s*def\s+(_vsp_guess_ci_run_dir_from_rid_v\d+)\s*\(', t)
guess_fn = guess_names[-1] if guess_names else None
if not guess_fn:
    print("[ERR] cannot find _vsp_guess_ci_run_dir_from_rid_v* in file")
    raise SystemExit(2)
print("[OK] guess_fn =", guess_fn)

# locate function _vsp_fix_status_from_body_v16
m = re.search(r'(?m)^def\s+_vsp_fix_status_from_body_v16\s*\(\s*resp\s*\)\s*:', t)
if not m:
    print("[ERR] cannot find def _vsp_fix_status_from_body_v16(resp):")
    raise SystemExit(3)

# extract function block by indentation
lines = t.splitlines(True)
cum = 0
start_i = None
for i, line in enumerate(lines):
    if cum <= m.start() < cum + len(line):
        start_i = i
        break
    cum += len(line)
if start_i is None:
    print("[ERR] internal mapping failed")
    raise SystemExit(4)

base_indent = re.match(r'^(\s*)', lines[start_i]).group(1)
base_col = len(base_indent)
end_i = len(lines)
for j in range(start_i + 1, len(lines)):
    s = lines[j]
    if s.strip() == "":
        continue
    ind = len(s) - len(s.lstrip(" "))
    if ind <= base_col and (s.lstrip().startswith("def ") or s.lstrip().startswith("@")):
        end_i = j
        break

fn_text = "".join(lines[start_i:end_i])

# find payload json-load line inside fn
# common patterns: payload = _json.loads(raw) / obj = _json.loads(body)
mload = re.search(r'(?m)^(?P<ind>\s*)(?P<var>payload|obj)\s*=\s*(?:_json|json)\.loads\(', fn_text)
if not mload:
    # fallback: find first line containing ".loads(" and assume payload var exists later
    mload = re.search(r'(?m)^(?P<ind>\s*).*(?:_json|json)\.loads\(', fn_text)
if not mload:
    print("[ERR] cannot find json.loads(...) line in _vsp_fix_status_from_body_v16")
    raise SystemExit(5)

ind = mload.group("ind")
var = mload.groupdict().get("var") or "payload"

inject = (
    ind + TAG + "\n"
    + ind + "try:\n"
    + ind + "    from flask import request as _req\n"
    + ind + "    _path = getattr(_req, 'path', '') or ''\n"
    + ind + "    # ensure defaults (avoid UI crash)\n"
    + ind + f"    if isinstance({var}, dict):\n"
    + ind + f"        {var}.setdefault('kics_verdict','')\n"
    + ind + f"        {var}.setdefault('kics_total',0)\n"
    + ind + f"        {var}.setdefault('kics_counts',{{}})\n"
    + ind + "    if _path.startswith('/api/vsp/run_status_v2/'):\n"
    + ind + "        _rid = _path.rsplit('/', 1)[-1]\n"
    + ind + f"        _ci = ({var}.get('ci_run_dir') if isinstance({var}, dict) else None) or {guess_fn}(_rid)\n"
    + ind + "        if _ci and isinstance(_ci, str) and _ci.strip():\n"
    + ind + f"            if isinstance({var}, dict):\n"
    + ind + f"                {var}['ci_run_dir'] = _ci\n"
    + ind + "            try:\n"
    + ind + "                import json as __json\n"
    + ind + "                from pathlib import Path as __P\n"
    + ind + "                _fp = __P(_ci) / 'kics' / 'kics_summary.json'\n"
    + ind + "                if _fp.exists():\n"
    + ind + "                    _raw = _fp.read_text(encoding='utf-8', errors='ignore') or ''\n"
    + ind + "                    _ks = __json.loads(_raw) if _raw.lstrip().startswith('{') else None\n"
    + ind + "                    if isinstance(_ks, dict) and isinstance({v}, dict):\n".format(v=var)
    + ind + "                        {v}['kics_verdict'] = (_ks.get('verdict') or '')\n".format(v=var)
    + ind + "                        {v}['kics_total']   = int(_ks.get('total', 0) or 0)\n".format(v=var)
    + ind + "                        _c = _ks.get('counts')\n"
    + ind + "                        {v}['kics_counts']  = (_c if isinstance(_c, dict) else {{}})\n".format(v=var)
    + ind + "            except Exception:\n"
    + ind + "                pass\n"
    + ind + "except Exception:\n"
    + ind + "    pass\n"
    + ind + "# === END VSP_FIX_STATUS_V16_INJECT_KICS_SUMMARY_V4 ===\n"
)

# inject right AFTER the json-load line (so payload/obj already exists)
pos = mload.end()
fn_text2 = fn_text[:pos] + "\n" + inject + fn_text[pos:]

full = "".join(lines)
full2 = full.replace(fn_text, fn_text2, 1)
p.write_text(full2, encoding="utf-8")
print("[OK] injected into _vsp_fix_status_from_body_v16")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
