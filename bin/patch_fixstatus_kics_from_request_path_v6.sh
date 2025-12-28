#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fixstatus_kics_fromreq_v6_${TS}"
echo "[BACKUP] $F.bak_fixstatus_kics_fromreq_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

FUNC = "_vsp_fix_status_from_body_v16"
TAG  = "# === VSP_FIX_STATUS_V16_INJECT_KICS_SUMMARY_FROM_REQUEST_V6 ==="

if TAG in t:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

m = re.search(r'(?m)^def\s+' + re.escape(FUNC) + r'\s*\(\s*resp\s*\)\s*:\s*$', t)
if not m:
    print(f"[ERR] cannot find def {FUNC}(resp):")
    raise SystemExit(2)

# Slice function block
start = m.start()
m2 = re.search(r'(?m)^\s*def\s+', t[m.end():])
end = (m.end() + m2.start()) if m2 else len(t)
fn = t[start:end]

# choose injection point BEFORE response is re-serialized
# prefer resp.set_data / _vsp_json_v16 / return resp
ins = None
for pat in [r'(?m)^\s+resp\.set_data\(', r'(?m)^\s+return\s+_vsp_json_v16\(', r'(?m)^\s+return\s+resp\s*$']:
    mm = re.search(pat, fn)
    if mm:
        ins = mm.start()
        break
if ins is None:
    print("[ERR] cannot find injection point in function (no resp.set_data / return _vsp_json_v16 / return resp)")
    raise SystemExit(3)

# Determine indent at injection point: take indentation of the matched line
line_start = fn.rfind("\n", 0, ins) + 1
indent = re.match(r'(\s*)', fn[line_start:]).group(1)

inject = f"""
{indent}{TAG}
{indent}try:
{indent}    # We are fixing status endpoints where RID is ONLY in URL, not in body JSON.
{indent}    from flask import request as _rq
{indent}    _path = (getattr(_rq, "path", "") or "")
{indent}    _rid = ""
{indent}    if _path.startswith("/api/vsp/run_status_v2/"):
{indent}        _rid = _path.split("/api/vsp/run_status_v2/", 1)[1]
{indent}    elif _path.startswith("/api/vsp/run_status_v1/"):
{indent}        _rid = _path.split("/api/vsp/run_status_v1/", 1)[1]
{indent}    _rid = (_rid.split("?", 1)[0]).strip()
{indent}    if _rid.startswith("RUN_"):
{indent}        _rid_norm = _rid[4:].strip()
{indent}    else:
{indent}        _rid_norm = _rid
{indent}
{indent}    # obj is the parsed JSON dict inside this function (already created above).
{indent}    if isinstance(locals().get("obj"), dict):
{indent}        # Fill ci_run_dir if missing
{indent}        if not obj.get("ci_run_dir"):
{indent}            try:
{indent}                ci = _vsp_guess_ci_run_dir_from_rid_v33(_rid_norm)
{indent}                if ci:
{indent}                    obj["ci_run_dir"] = ci
{indent}            except Exception:
{indent}                pass
{indent}
{indent}        ci = (obj.get("ci_run_dir") or "").strip()
{indent}        if ci:
{indent}            from pathlib import Path as _Path
{indent}            import json as _json
{indent}            ks = _Path(ci) / "kics" / "kics_summary.json"
{indent}            if ks.exists():
{indent}                try:
{indent}                    jj = _json.loads(ks.read_text(encoding="utf-8", errors="ignore") or "{{}}")
{indent}                    verdict = (jj.get("verdict") or "")
{indent}                    counts  = (jj.get("counts") or {{}})
{indent}                    total   = int(jj.get("total") or 0)
{indent}                    # OVERRIDE (commercial contract): if summary exists, it wins over empty defaults
{indent}                    obj["kics_verdict"] = verdict
{indent}                    obj["kics_counts"]  = counts
{indent}                    obj["kics_total"]   = total
{indent}                except Exception:
{indent}                    pass
{indent}except Exception:
{indent}    pass
"""

fn2 = fn[:ins] + inject + fn[ins:]
t2 = t[:start] + fn2 + t[end:]
p.write_text(t2, encoding="utf-8")
print("[OK] injected KICS summary from request.path into", FUNC)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] run_status_v2 (RID in URL) =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
