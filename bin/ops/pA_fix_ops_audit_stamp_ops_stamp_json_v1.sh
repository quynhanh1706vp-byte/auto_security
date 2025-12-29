#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/ops/ops_audit_stamp_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_ops_stamp_${TS}"
echo "[OK] backup => ${F}.bak_fix_ops_stamp_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/ops/ops_audit_stamp_v1.sh")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_OPS_AUDIT_STAMP_OPS_STAMP_JSON_FIX_V1"
if marker in s:
    print("[OK] already patched"); raise SystemExit(0)

# Replace the whole python heredoc that writes OPS_STAMP.json
pattern = r"""python3\s+-\s+<<'PY'\s+>\s+"\$OUT/OPS_STAMP\.json"\n.*?\nPY\n"""
m = re.search(pattern, s, flags=re.DOTALL)
if not m:
    raise SystemExit("[ERR] cannot locate OPS_STAMP.json python block")

replacement = r"""# 6) summary json
OUT_DIR="$OUT" BASE="$BASE" UNIT="$UNIT" python3 - <<'PY' > "$OUT/OPS_STAMP.json"
import json, os, re
from pathlib import Path

out = Path(os.environ["OUT_DIR"])
base = os.environ.get("BASE", "")
unit = os.environ.get("UNIT", "")

txt = (out/"runner_journal_tail.txt").read_text(encoding="utf-8", errors="replace") if (out/"runner_journal_tail.txt").exists() else ""
outj = {
  "ts": out.name,
  "base": base,
  "unit": unit,
  "runner_connected": bool(re.search(r"Connected to GitHub", txt, re.I)),
  "runner_ready": bool(re.search(r"Listening for Jobs", txt, re.I)),
  "evidence_dir": str(out),
}
print(json.dumps(outj, indent=2))
PY
# """ + marker + "\n"

s2 = s[:m.start()] + replacement + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched", marker)
PY

bash -n "$F"
echo "[OK] bash -n OK"
