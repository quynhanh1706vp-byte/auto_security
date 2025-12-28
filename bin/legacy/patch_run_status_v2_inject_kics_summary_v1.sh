#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runstatusv2_kics_${TS}"
echo "[BACKUP] $F.bak_runstatusv2_kics_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
t=p.read_text(encoding="utf-8", errors="ignore")

TAG="# === VSP_RUN_STATUS_V2_INJECT_KICS_SUMMARY_V1 ==="
if TAG in t:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# Find run_status_v2 function signature and its body region (best-effort).
m = re.search(r'(?ms)^\s*def\s+run_status_v2\s*\(\s*([A-Za-z_]\w*)\s*\)\s*:\s*\n', t)
if not m:
    print("[ERR] cannot find def run_status_v2(<arg>)")
    raise SystemExit(2)

arg = m.group(1)
start = m.end()

# Heuristic: function ends at next top-level "def " with same/lower indent.
m2 = re.search(r'(?m)^\s*def\s+\w+\s*\(', t[start:])
end = start + (m2.start() if m2 else len(t))

fn = t[start:end]

# Find "return jsonify(payload)" OR "return _jsonify(payload)" OR "return make_response(jsonify(payload))" patterns.
ret = re.search(r'(?m)^(?P<ind>\s*)return\s+.*jsonify\s*\(\s*payload\s*\).*$', fn)
if not ret:
    # fallback: any "return jsonify(" with payload variable
    ret = re.search(r'(?m)^(?P<ind>\s*)return\s+jsonify\s*\(\s*payload\s*\)\s*$', fn)

if not ret:
    print("[ERR] cannot find return ... jsonify(payload) inside run_status_v2")
    raise SystemExit(3)

indent = ret.group("ind")

inject = f"""
{indent}{TAG}
{indent}try:
{indent}    # Ensure ci_run_dir exists (run_status_v2 payload sometimes misses it)
{indent}    if not payload.get("ci_run_dir"):
{indent}        g = _vsp_guess_ci_run_dir_from_rid_v33(str({arg}))
{indent}        if g:
{indent}            payload["ci_run_dir"] = g
{indent}    ks = _vsp_read_kics_summary(payload.get("ci_run_dir",""))
{indent}    if isinstance(ks, dict):
{indent}        payload["kics_verdict"] = ks.get("verdict","") or ""
{indent}        payload["kics_counts"]  = ks.get("counts",{{}}) if isinstance(ks.get("counts"), dict) else {{}}
{indent}        payload["kics_total"]   = int(ks.get("total",0) or 0)
{indent}    else:
{indent}        payload.setdefault("kics_verdict","")
{indent}        payload.setdefault("kics_counts",{{}})
{indent}        payload.setdefault("kics_total",0)
{indent}except Exception:
{indent}    payload.setdefault("kics_verdict","")
{indent}    payload.setdefault("kics_counts",{{}})
{indent}    payload.setdefault("kics_total",0)
{indent}# === END VSP_RUN_STATUS_V2_INJECT_KICS_SUMMARY_V1 ===
"""

# Insert right before return line
fn2 = fn[:ret.start()] + inject + fn[ret.start():]
t2 = t[:start] + fn2 + t[end:]

p.write_text(t2, encoding="utf-8")
print("[OK] injected kics_summary into run_status_v2 (direct, deterministic)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sleep 1

curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
