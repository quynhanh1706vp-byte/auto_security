#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_rootredir_${TS}" && echo "[BACKUP] $F.bak_rootredir_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_ROOT_FORCE_REDIRECT_V1" in s:
    print("[OK] already patched")
    raise SystemExit(0)

m = re.search(r'^\s*(\w+)\s*=\s*Flask\s*\(', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find app = Flask(...)")
appvar = m.group(1)

hook = f"""
# ================================
# VSP_ROOT_FORCE_REDIRECT_V1
# ================================
from flask import redirect as _vsp_redirect
@{appvar}.before_request
def __vsp_force_root_to_vsp4_v1():
  try:
    # only force for exact root
    if request.path == "/":
      return _vsp_redirect("/vsp4/#dashboard", code=302)
  except Exception:
    pass
  return None
"""

# chèn ngay sau dòng app = Flask(...)
pos = m.end()
s2 = s[:pos] + "\n" + hook + "\n" + s[pos:]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted before_request root redirect on", appvar)
PY

python3 -m py_compile "$F" && echo "[OK] py_compile OK"

echo "== restart 8910 (NO restore) =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/ui_restart_8910_no_restore_v1.sh

echo "== verify root redirect =="
curl -sSI http://127.0.0.1:8910/ | head -n 12
echo "[NEXT] mở: http://127.0.0.1:8910/  (phải 302 -> /vsp4/#dashboard)"
