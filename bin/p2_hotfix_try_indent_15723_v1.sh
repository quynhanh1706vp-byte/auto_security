#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sed; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_hotfix_tryindent_${TS}"
echo "[BACKUP] ${F}.bak_hotfix_tryindent_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(errors="ignore").splitlines(True)

changed = 0

# Fix pattern:
#   try:
#   import os as _os
# -> indent import line under try
for i in range(len(lines) - 1):
    if re.match(r'^\s*try:\s*(#.*)?\n$', lines[i]) and re.match(r'^import\s+os\s+as\s+_os\b', lines[i+1]):
        lines[i+1] = "    " + lines[i+1]
        changed += 1

p.write_text("".join(lines))
print("[OK] try-indent fixes applied =", changed)

# must compile
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK")
PY

echo "== restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl daemon-reload || true
  sudo systemctl restart "$SVC"
fi

echo "== verify import (must be OK) =="
python3 - <<'PY'
import importlib.util, traceback
p="wsgi_vsp_ui_gateway.py"
spec=importlib.util.spec_from_file_location("wsgi_mod", p)
mod=importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
    app = getattr(mod,"application",None) or getattr(mod,"app",None)
    print("IMPORT_OK app_type=", type(app), "callable=", callable(app))
except Exception:
    traceback.print_exc()
    raise
PY

echo "[DONE] If systemd still fails, run: journalctl -xeu ${SVC} | tail -n 80"
