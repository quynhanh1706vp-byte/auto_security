#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="api/vsp_run_export_api_v3.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_usehint_${TS}"
echo "[BACKUP] $F.bak_usehint_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("api/vsp_run_export_api_v3.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_EXPORT_RUN_DIR_HINT"
if marker in s:
    print("[OK] hint already referenced; skip")
    raise SystemExit(0)

# Insert after first place where run_dir is assigned (best effort)
pat = r'(?m)^\s*run_dir\s*=\s*.*\n'
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find run_dir assignment in export api")

ins = "\n    _hint = os.environ.get(\"VSP_EXPORT_RUN_DIR_HINT\")\n    if _hint and os.path.isdir(_hint):\n        run_dir = _hint\n"
idx = m.end()
s = s[:idx] + ins + s[idx:]

p.write_text(s, encoding="utf-8")
print("[OK] inserted run_dir hint usage")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
