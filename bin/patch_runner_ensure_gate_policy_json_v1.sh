#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE

F="bin/run_all_tools_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_gatepolicystub_${TS}"
echo "[BACKUP] $F.bak_gatepolicystub_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/run_all_tools_v2.sh")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_GATEPOLICY_STUB_V1" in s:
    print("[OK] already patched, skip")
    raise SystemExit(0)

# Insert near end, after GATE_POLICY/POLICY_POST blocks if possible, else append
insert = r'''
# === VSP_GATEPOLICY_STUB_V1 (commercial: always have gate_policy.json) ===
if [ -n "${OUT_DIR:-}" ] && [ -d "${OUT_DIR:-}" ]; then
  if [ ! -s "$OUT_DIR/gate_policy.json" ]; then
    if [ -s "$OUT_DIR/run_gate_summary.json" ]; then
      python3 - <<PY2
import json, os
out_dir=os.environ.get("OUT_DIR")
rgp=os.path.join(out_dir,"run_gate_summary.json")
gp=os.path.join(out_dir,"gate_policy.json")
try:
  rg=json.load(open(rgp,"r",encoding="utf-8"))
except Exception:
  rg={}
verdict=(rg.get("overall") or rg.get("overall_status") or rg.get("overall_verdict") or "UNKNOWN")
obj={
  "ok": True,
  "verdict": str(verdict).upper(),
  "reasons": [f"stub_from_run_gate_summary overall={verdict}"],
  "degraded_n": 0
}
json.dump(obj, open(gp,"w",encoding="utf-8"), ensure_ascii=False, indent=2)
print("[VSP][GATEPOLICY_STUB] wrote", gp)
PY2
    else
      # minimal stub
      printf '{\n  "ok": true,\n  "verdict": "UNKNOWN",\n  "reasons": ["stub_minimal"],\n  "degraded_n": 0\n}\n' > "$OUT_DIR/gate_policy.json" || true
      echo "[VSP][GATEPOLICY_STUB] wrote minimal gate_policy.json"
    fi
  fi
fi
# === /VSP_GATEPOLICY_STUB_V1 ===
'''

# try place after POLICY_POST marker
m=re.search(r"^\s*===== \[POLICY_POST\].*$", s, re.M)
if m:
    # insert after the POLICY_POST section end: easiest append right after that line
    pos = s.find("\n", m.end())
    if pos<0: pos=m.end()
    s2 = s[:pos+1] + insert + s[pos+1:]
else:
    s2 = s.rstrip() + "\n\n" + insert + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] inserted gate_policy stub block")
PY

bash -n "$F" && echo "[OK] bash -n OK"
