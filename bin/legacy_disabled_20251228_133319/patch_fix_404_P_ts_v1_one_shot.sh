#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

echo "== FIX 404 /PYYMMDD_HHMMSS =="

# --- A) remove any line containing /P######_###### from templates (best-effort) ---
fix_tpl () {
  local T="$1"
  [ -f "$T" ] || return 0
  cp -f "$T" "$T.bak_fixP404_${TS}" && echo "[BACKUP] $T.bak_fixP404_${TS}"
  python3 - <<PY
from pathlib import Path
import re
p=Path("$T")
s=p.read_text(encoding="utf-8", errors="replace")
# remove any HTML line that references /P######_###### (src/href/etc)
s2=re.sub(r'(?m)^.*?/P\\d{6}_\\d{6}.*\\n', '', s)
p.write_text(s2, encoding="utf-8")
print("[OK] cleaned /P######_###### from", "$T")
PY
}
fix_tpl templates/vsp_4tabs_commercial_v1.html
fix_tpl templates/vsp_dashboard_2025.html

# --- B) add backend route to return 204 for /P######_###### (silence leftover calls) ---
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_fixP404_${TS}" && echo "[BACKUP] $F.bak_fixP404_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# ensure "import re" exists
if not re.search(r'(?m)^\s*import\s+re\s*$', s):
  s = re.sub(r'(?m)^(\s*import\s+[^\n]+\n)', r'\1import re\n', s, count=1)

MARK_B="### VSP_ROUTE_P_TS_204_BEGIN"
MARK_E="### VSP_ROUTE_P_TS_204_END"
s=re.sub(re.escape(MARK_B)+r"[\s\S]*?"+re.escape(MARK_E)+r"\n?", "", s)

block = r'''
### VSP_ROUTE_P_TS_204_BEGIN
@app.route("/P<token>")
def vsp_p_ts_204(token):
    # Some UI patches may accidentally embed /PYYMMDD_HHMMSS as a resource.
    # Return 204 to avoid console 404 noise; otherwise keep 404.
    try:
        if re.fullmatch(r"\d{6}_\d{6}", token or ""):
            return ("", 204, {
                "Cache-Control": "no-store",
                "Pragma": "no-cache",
            })
    except Exception:
        pass
    return ({"ok": False, "reason": "not_found"}, 404)
### VSP_ROUTE_P_TS_204_END
'''

# inject near other routes: append before "if __name__" or at end
if "if __name__" in s:
  s = s.replace("if __name__ ==", block + "\n\nif __name__ ==", 1)
else:
  s = s + "\n\n" + block + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] injected /P<token> 204 route")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"

echo "[DONE] Patch applied. Restart 8910 + hard refresh Ctrl+Shift+R."
