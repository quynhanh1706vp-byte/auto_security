#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time, shutil

root = Path("static/js")
if not root.exists():
    raise SystemExit("[ERR] static/js not found")

# 1) locate bundle that contains our autorefresh marker
marker = "VSP_P1_RULE_OVERRIDES_AUTOREFRESH_V1"
cands = []
for p in sorted(root.glob("*.js")):
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if marker in s:
        cands.append(p)

if not cands:
    raise SystemExit(f"[ERR] cannot find any *.js containing {marker}")

bundle = cands[0]
ts = time.strftime("%Y%m%d_%H%M%S")
bak = bundle.with_name(bundle.name + f".bak_fix_true_{ts}")
shutil.copy2(bundle, bak)
print("[BACKUP]", bak)

s = bundle.read_text(encoding="utf-8", errors="replace")
before = s

# 2) fix invalid JS token True -> true in the "ok" expression
# handle patterns:
#   j.ok === True
#   (j.ok === True || j.ok === true ...)
s = re.sub(r'\bj\.ok\s*===\s*True\b', 'j.ok === true', s)

# also remove any stray "=== True ||" fragments if present
s = re.sub(r'\bj\.ok\s*===\s*true\s*\|\|\s*', 'j.ok === true || ', s)

if s == before:
    print("[WARN] no change applied (maybe already fixed).")
else:
    bundle.write_text(s, encoding="utf-8")
    print("[OK] patched True->true in:", bundle)

# 3) quick confirmation
m = re.search(r'VSP_P1_RULE_OVERRIDES_AUTOREFRESH_V1[\s\S]{0,800}?\bok\s*=\s*!!\(', s)
print("[INFO] marker present:", marker in s)
PY

echo "== grep around marker (sanity) =="
grep -n "VSP_P1_RULE_OVERRIDES_AUTOREFRESH_V1" -n static/js/*.js | head -n 10 || true
echo "[NEXT] restart UI + hard refresh (Ctrl+F5)."
