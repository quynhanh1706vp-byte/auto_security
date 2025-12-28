#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need tail; need mkdir; need sed; need grep

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
LOG="out_ci/ui_8910.error.log"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
mkdir -p out_ci

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_boot_exports_${TS}"
echo "[BACKUP] ${F}.bak_boot_exports_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import re, sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
orig=s

# Remove older export blocks if present (our previous markers)
s = re.sub(r'(?s)\n# --- VSP_P1_EXPORT_APP_APPLICATION_V1.*?\n(?=\Z)', "\n", s)
s = re.sub(r'(?s)\n# --- VSP_BOOT_EXPORTS_V1.*?\n(?=\Z)', "\n", s)

# Append robust export block (never breaks gunicorn callable resolution)
block = r'''
# --- VSP_BOOT_EXPORTS_V1 (robust gunicorn callable exports) ---
def __vsp_pick_callable():
    g = globals()
    cand = []
    # prefer explicit 'application' if it's callable
    if "application" in g and callable(g.get("application")):
        return g["application"]
    # common flask names
    if "app" in g and callable(g.get("app")):
        return g["app"]
    if "flask_app" in g and callable(g.get("flask_app")):
        return g["flask_app"]
    # factory patterns
    if "create_app" in g and callable(g.get("create_app")):
        try:
            return g["create_app"]()
        except Exception:
            pass
    if "create_application" in g and callable(g.get("create_application")):
        try:
            return g["create_application"]()
        except Exception:
            pass
    return None

# ensure both names exist for gunicorn/legacy imports
__picked = __vsp_pick_callable()
if __picked is not None:
    application = __picked
    app = __picked
# --- end VSP_BOOT_EXPORTS_V1 ---
'''
s = s.rstrip() + "\n" + block + "\n"

if s != orig:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched exports block appended")
else:
    print("[WARN] no change (unexpected)")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }

echo "== [1] quick import test =="
python3 - <<'PY'
import importlib, traceback
try:
    m=importlib.import_module("wsgi_vsp_ui_gateway")
    a=getattr(m,"application",None)
    ap=getattr(m,"app",None)
    print("import OK")
    print("application:", type(a).__name__, "callable=", callable(a))
    print("app:", type(ap).__name__, "callable=", callable(ap))
except Exception as e:
    print("import FAIL:", e)
    traceback.print_exc()
    raise
PY

echo "== [2] restart service =="
systemctl restart "$SVC" || true
sleep 0.8

echo "== [3] status (short) =="
systemctl status "$SVC" -l --no-pager | head -n 80 || true

echo "== [4] last error log lines =="
if [ -f "$LOG" ]; then
  tail -n 120 "$LOG" || true
else
  echo "[WARN] missing $LOG (gunicorn may not start far enough to create it)"
fi

echo "== [5] smoke curl =="
curl -fsS --connect-timeout 1 http://127.0.0.1:8910/runs >/dev/null && echo "[OK] /runs reachable" || echo "[ERR] /runs still not reachable"
