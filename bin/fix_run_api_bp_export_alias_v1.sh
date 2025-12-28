#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PYF="run_api/vsp_run_api_v1.py"
[ -f "$PYF" ] || { echo "[ERR] missing: $PYF"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$PYF" "$PYF.bak_bp_alias_${TS}"
echo "[BACKUP] $PYF.bak_bp_alias_${TS}"

python3 - << 'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# If already exported, do nothing
if re.search(r"(?m)^\s*bp_vsp_run_api_v1\s*=\s*", txt):
    print("[OK] bp_vsp_run_api_v1 already exists")
    raise SystemExit(0)

# Find first blueprint variable assignment: <var> = Blueprint(...)
m = re.search(r"(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*Blueprint\s*\(", txt)
if not m:
    print("[ERR] Cannot find any Blueprint(...) assignment in run_api/vsp_run_api_v1.py")
    print("      Ensure you define something like: bp = Blueprint('...', __name__)")
    raise SystemExit(2)

bp_var = m.group(1)

# Append alias exports (idempotent-ish)
addon = f"""

# === VSP_COMMERCIAL_BP_EXPORT_ALIAS_V1 ===
# Backward-compatible export name expected by UI gateway:
bp_vsp_run_api_v1 = {bp_var}
# Optional: keep old name too (some code may import bp_vsp_run_api)
try:
    bp_vsp_run_api
except NameError:
    bp_vsp_run_api = {bp_var}
# === END VSP_COMMERCIAL_BP_EXPORT_ALIAS_V1 ===
"""

txt2 = txt.rstrip() + "\n" + addon
p.write_text(txt2, encoding="utf-8")
print("[OK] Added bp_vsp_run_api_v1 alias ->", bp_var)
PY

python3 -m py_compile "$PYF"
echo "[OK] run_api py_compile OK"

echo "== GREP exports =="
grep -nE "bp_vsp_run_api_v1|VSP_COMMERCIAL_BP_EXPORT_ALIAS_V1" "$PYF" | tail -n 10
echo "[DONE]"
