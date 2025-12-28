#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"

echo "== (1) restore last known-good backup =="
B="$(ls -1t vsp_demo_app.py.bak_rootredir_* vsp_demo_app.py.bak_vsp4_inject_* 2>/dev/null | head -n1 || true)"
[ -n "$B" ] || { echo "[ERR] no backup found (bak_rootredir_* or bak_vsp4_inject_*)"; exit 2; }

cp -f "$B" "$F"
echo "[RESTORE] $F <= $B"

python3 -m py_compile "$F" && echo "[OK] py_compile OK after restore"

echo "== (2) append ROOT redirect V2 safely (at EOF) =="
python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_ROOT_FORCE_REDIRECT_V2" in s:
    print("[OK] redirect V2 already present")
    raise SystemExit(0)

m = re.search(r'^\s*(\w+)\s*=\s*Flask\s*\(', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find app = Flask(...)")
appvar = m.group(1)

block = f"""
# ================================
# VSP_ROOT_FORCE_REDIRECT_V2
# ================================
try:
  from flask import redirect as _vsp_redirect
except Exception:
  _vsp_redirect = None

@{appvar}.before_request
def __vsp_force_root_to_vsp4_v2():
  try:
    # exact root only
    if request.path == "/" and _vsp_redirect is not None:
      return _vsp_redirect("/vsp4/#dashboard", code=302)
  except Exception:
    pass
  return None
"""

p.write_text(s + "\n" + block + "\n", encoding="utf-8")
print("[OK] appended redirect V2 on", appvar)
PY

python3 -m py_compile "$F" && echo "[OK] py_compile OK after patch"

echo "== (3) restart 8910 (NO restore) =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/ui_restart_8910_no_restore_v1.sh

echo "== (4) verify redirect now =="
curl -sSI http://127.0.0.1:8910/ | head -n 12 || true
echo
echo "[NEXT] mở: http://127.0.0.1:8910/  (phải 302 sang /vsp4/#dashboard)"
