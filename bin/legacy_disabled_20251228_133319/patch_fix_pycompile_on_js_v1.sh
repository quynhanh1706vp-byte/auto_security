#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/patch_ui_p2_drilldown_to_datasource_table_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_pycompile_js_${TS}"
echo "[BACKUP] $F.bak_fix_pycompile_js_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/patch_ui_p2_drilldown_to_datasource_table_v1.sh")
t = p.read_text(encoding="utf-8", errors="ignore")

# remove wrong py_compile lines for .js
t2 = re.sub(r"\npython3\s+-m\s+py_compile\s+static/js/vsp_dashboard_enhance_v1\.js\s+static/js/vsp_datasource_tab_v1\.js\s*\n", "\n", t)
t2 = re.sub(r"\necho\s+\"\[OK\]\s+py_compile\s+OK\"\s*\n", "\n", t2)

# inject node --check (optional) right after the PY block ends (after the line 'PY')
marker = "\nPY\n\n"
ins = """PY

# JS syntax check (commercial)
if command -v node >/dev/null 2>&1; then
  node --check static/js/vsp_dashboard_enhance_v1.js
  node --check static/js/vsp_datasource_tab_v1.js
  echo "[OK] node --check JS syntax OK"
else
  echo "[SKIP] node not found; skip JS syntax check"
fi

"""

if marker in t2 and ins not in t2:
    t2 = t2.replace(marker, "\n" + ins, 1)

p.write_text(t2, encoding="utf-8")
print("[OK] patched: removed python py_compile on .js; added optional node --check")
PY

chmod +x "$F"
echo "[DONE] Now rerun:"
echo "  /home/test/Data/SECURITY_BUNDLE/ui/$F"
