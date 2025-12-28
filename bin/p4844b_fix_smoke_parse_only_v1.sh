#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="bin/p4844_rescue_runs_v3_parens_and_contract_mw_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p4844b_${TS}"
echo "[OK] backup => ${F}.bak_p4844b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/p4844_rescue_runs_v3_parens_and_contract_mw_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace the broken heredoc+stdin usage with a safe file-read parse
pat = r'python3\s+-\s+<<\'PY\'\s+<\"\$OUT/body\.json\".*?^PY\s*$'
rep = r'''python3 - <<'PY' | tee -a "$OUT/log.txt"
import json, pathlib
p = pathlib.Path(__file__).resolve().parent.parent / "out_ci" / pathlib.Path("$OUT").name / "body.json"
j = json.loads(p.read_text(encoding="utf-8", errors="replace"))
print("keys=", sorted(j.keys()))
print("items_len=", len(j.get("items") or []) if isinstance(j.get("items"), list) else type(j.get("items")).__name__)
print("runs_len=", len(j.get("runs") or []) if isinstance(j.get("runs"), list) else type(j.get("runs")).__name__)
print("total=", j.get("total"))
PY'''
s2, n = re.subn(pat, rep, s, flags=re.M|re.S)
if n == 0:
    print("[WARN] pattern not found; no changes")
else:
    print(f"[OK] patched smoke parse block: {n}")
p.write_text(s2, encoding="utf-8")
PY
