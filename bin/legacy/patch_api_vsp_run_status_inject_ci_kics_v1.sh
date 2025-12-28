#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_api_status_ci_kics_v1_${TS}"
echo "[BACKUP] $F.bak_api_status_ci_kics_v1_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
t=p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

FUNC="api_vsp_run_status"
TAG="# === VSP_API_VSP_RUN_STATUS_INJECT_CI_KICS_V1 ==="

# find def
def_re = re.compile(r'^([ \t]*)def\s+'+re.escape(FUNC)+r'\s*\([^)]*\)\s*:\s*$')
i0=None; indent0=""
for i,l in enumerate(t):
    m=def_re.match(l)
    if m:
        i0=i; indent0=m.group(1); break
if i0 is None:
    raise SystemExit("[ERR] cannot find def api_vsp_run_status(...)")

# find block end by dedent
i1=None
for j in range(i0+1, len(t)):
    lj=t[j]
    if lj.strip()=="":
        continue
    # dedent: not deeper than indent0
    if not (lj.startswith(indent0) and len(lj)>len(indent0) and lj[len(indent0)] in (" ","\t")):
        i1=j; break
if i1 is None:
    i1=len(t)

block="".join(t[i0:i1])
if TAG in block:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# find last return line inside function (prefer return jsonify(...) / return _vsp_json_v16(...) / return resp)
ret_idx=None
for k in range(i1-1, i0, -1):
    if re.search(r'^\s*return\b', t[k]):
        ret_idx=k
        break
if ret_idx is None:
    raise SystemExit("[ERR] cannot find any 'return' inside api_vsp_run_status")

indent_ret = re.match(r'^([ \t]*)', t[ret_idx]).group(1)

inj = f"""{indent_ret}{TAG}
{indent_ret}try:
{indent_ret}    # ensure payload exists + is dict
{indent_ret}    _pl = payload if isinstance(locals().get("payload", None), dict) else None
{indent_ret}    if _pl is None:
{indent_ret}        _pl = locals().get("obj", None) if isinstance(locals().get("obj", None), dict) else None
{indent_ret}    if _pl is not None:
{indent_ret}        _rid = (req_id or "").strip()
{indent_ret}        _ci = (_pl.get("ci_run_dir") or "").strip()
{indent_ret}        if not _ci:
{indent_ret}            try:
{indent_ret}                _ci = _vsp_guess_ci_run_dir_from_rid_v33(_rid) or ""
{indent_ret}            except Exception:
{indent_ret}                _ci = ""
{indent_ret}            if _ci:
{indent_ret}                _pl["ci_run_dir"] = _ci
{indent_ret}        if _ci:
{indent_ret}            # inject KICS summary (if exists)
{indent_ret}            try:
{indent_ret}                import json as _json
{indent_ret}                from pathlib import Path as _Path
{indent_ret}                _ks = _Path(_ci) / "kics" / "kics_summary.json"
{indent_ret}                if _ks.is_file():
{indent_ret}                    _ko = _json.loads(_ks.read_text(encoding="utf-8", errors="ignore") or "{{}}")
{indent_ret}                    if isinstance(_ko, dict):
{indent_ret}                        _pl["kics_verdict"] = _ko.get("verdict","") or _pl.get("kics_verdict","")
{indent_ret}                        try:
{indent_ret}                            _pl["kics_total"] = int(_ko.get("total") or 0)
{indent_ret}                        except Exception:
{indent_ret}                            pass
{indent_ret}                        _pl["kics_counts"] = _ko.get("counts") or _pl.get("kics_counts") or {{}}
{indent_ret}            except Exception:
{indent_ret}                pass
{indent_ret}except Exception:
{indent_ret}    pass

"""

t2 = t[:ret_idx] + [inj] + t[ret_idx:]
p.write_text("".join(t2), encoding="utf-8")
print("[OK] injected before last return at line", ret_idx+1)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
