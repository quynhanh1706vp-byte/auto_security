#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_gatev3logfix_${TS}"
echo "[BACKUP] $F.bak_gatev3logfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_GATE_POLICY_V3_LOG_FALLBACK_V2" in s:
    print("[OK] already patched, skip")
    raise SystemExit(0)

# Find the exact terminal block (allow whitespace variations)
pat = re.compile(
    r'resp\["reasons"\]\s*=\s*\["gate_policy\.json missing",\s*"run_gate_summary\.json missing"\]\s*\n'
    r'\s*resp\["ok"\]\s*=\s*True\s*\n'
    r'\s*resp\["source"\]\s*=\s*"none"\s*\n'
    r'\s*return resp',
    re.M
)

m = pat.search(s)
if not m:
    print("[ERR] cannot locate tail block (source=none) to patch")
    raise SystemExit(2)

new_block = r'''# --- VSP_GATE_POLICY_V3_LOG_FALLBACK_V2 ---
    # fallback: parse SUMMARY.txt / runner.log so UI always has a badge
    try:
        import re as _re
        def _read_txt(_p):
            try:
                with open(_p, "r", encoding="utf-8", errors="ignore") as _f:
                    return _f.read()
            except Exception:
                return ""

        summ = _read_txt(os.path.join(run_dir, "SUMMARY.txt"))
        rlog = _read_txt(os.path.join(run_dir, "runner.log"))

        # 1) Prefer SUMMARY.txt line: [GATE_POLICY] verdict=RED reasons=...
        mm = _re.search(r"\[GATE_POLICY\]\s+verdict=([A-Z]+)\s+reasons=([^\n]+)", summ)
        if mm:
            resp["verdict"] = _gp_norm_verdict(mm.group(1))
            resp["reasons"] = [mm.group(2).strip(), "fallback:SUMMARY.txt", "gate_policy.json missing"]
            resp["ok"] = True
            resp["source"] = "SUMMARY.txt"
            return resp

        # 2) Fallback runner.log: [RUN_GATE][OK] overall=RED ...
        mm = _re.search(r"\[RUN_GATE\]\[OK\]\s+overall=([A-Z]+)\b", rlog)
        if mm:
            resp["verdict"] = _gp_norm_verdict(mm.group(1))
            resp["reasons"] = [f"fallback:runner.log overall={resp['verdict']}", "gate_policy.json missing", "run_gate_summary.json missing"]
            resp["ok"] = True
            resp["source"] = "runner.log"
            return resp

    except Exception:
        pass

    resp["reasons"] = ["gate_policy.json missing", "run_gate_summary.json missing"]
    resp["ok"] = True
    resp["source"] = "none"
    return resp
# --- /VSP_GATE_POLICY_V3_LOG_FALLBACK_V2 ---'''

s2 = s[:m.start()] + new_block + s[m.end():] + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] patched tail block to include log fallback")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 gunicorn"
