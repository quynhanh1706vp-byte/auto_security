#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/patch_ui_p2_fix_datasource_root_guard_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_pycompile_js_${TS}"
echo "[BACKUP] $F.bak_fix_pycompile_js_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/patch_ui_p2_fix_datasource_root_guard_v1.sh")
t = p.read_text(encoding="utf-8", errors="ignore")

# remove py_compile on JS
t = re.sub(r"\npython3\s+-m\s+py_compile\s+static/js/vsp_datasource_tab_v1\.js\s*\n", "\n", t)
t = re.sub(r"\necho\s+\"\[OK\]\s+py_compile\s+OK\"\s*\n", "\n", t)

# inject node --check after the python heredoc ends (after 'PY')
marker = "\nPY\n\n"
ins = """PY

# JS syntax check (commercial)
if command -v node >/dev/null 2>&1; then
  node --check static/js/vsp_datasource_tab_v1.js
  echo "[OK] node --check JS syntax OK"
else
  echo "[SKIP] node not found; skip JS syntax check"
fi

"""

if marker in t and ins not in t:
    t = t.replace(marker, "\n" + ins, 1)

p.write_text(t, encoding="utf-8")
print("[OK] patched rootguard script: removed py_compile on .js; added node --check")
PY

chmod +x "$F"
echo "[DONE] Now you can rerun rootguard safely:"
echo "  /home/test/Data/SECURITY_BUNDLE/ui/$F"
