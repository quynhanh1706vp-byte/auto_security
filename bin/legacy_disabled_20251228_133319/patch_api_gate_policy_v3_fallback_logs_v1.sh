#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_gatev3log_${TS}"
echo "[BACKUP] $F.bak_gatev3log_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_GATE_POLICY_V3_LOG_FALLBACK_V1" in s:
    print("[OK] already patched, skip")
    raise SystemExit(0)

# replace the exact "source=none" terminal block we injected earlier
pat = re.compile(
    r'resp\["reasons"\]=\["gate_policy\.json missing", "run_gate_summary\.json missing"\]\s*\n'
    r'\s*resp\["ok"\]=True\s*\n'
    r'\s*resp\["source"\]="none"\s*\n'
    r'\s*return resp',
    re.M
)

rep = r'''# --- VSP_GATE_POLICY_V3_LOG_FALLBACK_V1 ---
    # fallback: parse SUMMARY.txt / runner.log to get verdict so UI is never "blank"
    try:
        import re as _re
        def _read_txt(_p):
            try:
                with open(_p,"r",encoding="utf-8",errors="ignore") as _f:
                    return _f.read()
            except Exception:
                return ""
        summ=_read_txt(os.path.join(run_dir,"SUMMARY.txt"))
        rlog=_read_txt(os.path.join(run_dir,"runner.log"))

        # 1) prefer [GATE_POLICY] verdict=XXX reasons=...
        m=_re.search(r"\[GATE_POLICY\]\s+verdict=([A-Z]+)\s+reasons=([^\n]+)", summ)
        if m:
            resp["verdict"]=_gp_norm_verdict(m.group(1))
            resp["reasons"]=[m.group(2).strip(), "fallback:SUMMARY.txt", "gate_policy.json missing"]
            resp["ok"]=True
            resp["source"]="SUMMARY.txt"
            return resp

        # 2) fallback [RUN_GATE][OK] overall=XXX ...
        m=_re.search(r"\[RUN_GATE\]\[OK\]\s+overall=([A-Z]+)\b", rlog)
        if m:
            resp["verdict"]=_gp_norm_verdict(m.group(1))
            resp["reasons"]=[f"fallback:runner.log overall={resp['verdict']}", "gate_policy.json missing", "run_gate_summary.json missing"]
            resp["ok"]=True
            resp["source"]="runner.log"
            return resp

    except Exception:
        pass

    resp["reasons"]=["gate_policy.json missing", "run_gate_summary.json missing"]
    resp["ok"]=True
    resp["source"]="none"
    return resp
# --- /VSP_GATE_POLICY_V3_LOG_FALLBACK_V1 ---'''

s2, n = pat.subn(rep, s, count=1)
if n != 1:
    print("[ERR] cannot find source=none terminal block to patch (pattern mismatch).")
    raise SystemExit(2)

p.write_text(s2, encoding="utf-8")
print("[OK] patched gate_policy_v3 fallback to logs")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 gunicorn"
