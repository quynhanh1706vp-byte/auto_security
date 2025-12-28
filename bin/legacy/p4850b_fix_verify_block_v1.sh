#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p4850_commercial_runs3_contract_items_alias_backend_frontend_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p4850b_${TS}"
echo "[OK] backup => ${F}.bak_p4850b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/p4850_commercial_runs3_contract_items_alias_backend_frontend_v1.sh")
s = p.read_text(encoding="utf-8", errors="replace")

# Replace the broken verify python block (FileNotFoundError due to wrong quoting)
pat = re.compile(r'python3\s+-\s+<<\'PY\'\s+\|\s+tee\s+-a\s+"\$OUT/log\.txt"\n.*?\nPY\n', re.S)

replacement = r'''python3 - <<PY | tee -a "$OUT/log.txt"
import json, pathlib
p = pathlib.Path("$BODY")
j = json.loads(p.read_text(encoding="utf-8", errors="replace"))
print("keys=", sorted(j.keys()))
print("items_type=", type(j.get("items")).__name__, "items_len=", (len(j["items"]) if isinstance(j.get("items"), list) else "NA"))
print("runs_type=", type(j.get("runs")).__name__, "runs_len=", (len(j["runs"]) if isinstance(j.get("runs"), list) else "NA"))
print("total=", j.get("total"))
PY
'''

s2, n = pat.subn(replacement, s, count=1)
if n != 1:
    raise SystemExit(f"[ERR] cannot patch verify block (pattern not found). n={n}")

p.write_text(s2, encoding="utf-8")
print("[OK] patched verify block:", n)
PY
