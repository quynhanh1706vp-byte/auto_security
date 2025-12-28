#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="$(ls -1t out_ci/p4848c_*/log.txt 2>/dev/null | head -n1 | xargs -r dirname)/../p4848c_runs_v3_items_alias_after_request_mw_v3.sh"
# fallback: patch the script in bin/
F="bin/p4848c_runs_v3_items_alias_after_request_mw_v3.sh"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixverify_${TS}"
echo "[OK] backup => ${F}.bak_fixverify_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/p4848c_runs_v3_items_alias_after_request_mw_v3.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace the bad "<$OUT/body.json" verify block to a safe file-read parser
s2 = re.sub(
    r'python3\s+-\s+<<\'PY\'\s+<\"\$OUT/body\.json\".*?^PY\s*$',
    r'''python3 - <<'PY' | tee -a "$OUT/log.txt"
import json, pathlib
j = json.loads(pathlib.Path("$OUT/body.json").read_text(encoding="utf-8", errors="replace"))
print("keys=", sorted(j.keys()))
print("items_type=", type(j.get("items")).__name__, "runs_type=", type(j.get("runs")).__name__)
print("items_len=", len(j.get("items") or []) if isinstance(j.get("items"), list) else "NA")
print("runs_len=", len(j.get("runs") or []) if isinstance(j.get("runs"), list) else "NA")
print("total=", j.get("total"))
PY''',
    s,
    flags=re.M | re.S
)

if s2 == s:
    print("[WARN] verify block pattern not found; no changes")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] verify block patched")
PY
