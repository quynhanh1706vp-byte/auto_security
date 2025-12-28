#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fixstatus_ci_kics_v9_${TS}"
echo "[BACKUP] $F.bak_fixstatus_ci_kics_v9_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

FUNC = "_vsp_fix_status_from_body_v16"
TAG  = "# === VSP_FIX_STATUS_INJECT_CI_KICS_V9 ==="

# find function def
def_re = re.compile(r'^([ \t]*)def\s+' + re.escape(FUNC) + r'\s*\([^)]*\)\s*:\s*$')
i0=None; indent0=""
for i,l in enumerate(lines):
    m=def_re.match(l)
    if m:
        i0=i; indent0=m.group(1); break
if i0 is None:
    raise SystemExit(f"[ERR] cannot find def {FUNC}(...):")

# find function end by dedent
i1=None
for j in range(i0+1, len(lines)):
    lj=lines[j]
    if lj.strip()=="":
        continue
    if not (lj.startswith(indent0) and len(lj)>len(indent0) and lj[len(indent0)] in (" ","\t")):
        i1=j; break
if i1 is None:
    i1=len(lines)

block = "".join(lines[i0:i1])
if TAG in block:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# find the JSON loads assignment inside function to get var name (obj/whatever)
var=None; ins=None; ins_indent=None
assign_re = re.compile(r'^([ \t]*)([A-Za-z_]\w*)\s*=\s*(?:_json|json)\.loads\(')
for k in range(i0, i1):
    m=assign_re.match(lines[k])
    if m:
        ins = k+1
        ins_indent = m.group(1)
        var = m.group(2)
        break

if ins is None:
    # fallback: any " = ...loads(" line
    fallback = re.compile(r'^([ \t]*)([A-Za-z_]\w*)\s*=\s*.*loads\(')
    for k in range(i0, i1):
        m=fallback.match(lines[k])
        if m:
            ins = k+1
            ins_indent = m.group(1)
            var = m.group(2)
            break

if ins is None or var is None:
    raise SystemExit("[ERR] cannot find json.loads(...) assignment inside _vsp_fix_status_from_body_v16")

inj = f"""{ins_indent}{TAG}
{ins_indent}try:
{ins_indent}    from flask import request as _req
{ins_indent}    _path = getattr(_req, "path", "") or ""
{ins_indent}    if _path.startswith("/api/vsp/run_status_v2/"):
{ins_indent}        _rid = (_path.rsplit("/", 1)[-1] or "").strip()
{ins_indent}        _ci = ""
{ins_indent}        try:
{ins_indent}            _ci = _vsp_guess_ci_run_dir_from_rid_v33(_rid) or ""
{ins_indent}        except Exception:
{ins_indent}            _ci = ""
{ins_indent}        if isinstance({var}, dict):
{ins_indent}            if _ci:
{ins_indent}                {var}["ci_run_dir"] = _ci
{ins_indent}            # inject KICS summary (if present)
{ins_indent}            if _ci:
{ins_indent}                try:
{ins_indent}                    import json as _json2
{ins_indent}                    from pathlib import Path as _P
{ins_indent}                    _ks = _P(_ci) / "kics" / "kics_summary.json"
{ins_indent}                    if _ks.is_file():
{ins_indent}                        _ko = _json2.loads(_ks.read_text(encoding="utf-8", errors="ignore") or "{{}}")
{ins_indent}                        if isinstance(_ko, dict):
{ins_indent}                            {var}["kics_verdict"] = _ko.get("verdict","") or {var}.get("kics_verdict","")
{ins_indent}                            try:
{ins_indent}                                {var}["kics_total"] = int(_ko.get("total") or 0)
{ins_indent}                            except Exception:
{ins_indent}                                pass
{ins_indent}                            {var}["kics_counts"] = _ko.get("counts") or {var}.get("kics_counts") or {{}}
{ins_indent}                except Exception:
{ins_indent}                    pass
{ins_indent}except Exception:
{ins_indent}    pass

"""

lines2 = lines[:ins] + [inj] + lines[ins:]
p.write_text("".join(lines2), encoding="utf-8")
print(f"[OK] injected after loads var={var} at line {ins+1}")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
