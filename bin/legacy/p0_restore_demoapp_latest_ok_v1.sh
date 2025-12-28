#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_before_restore_${TS}"
echo "[BACKUP] ${APP}.bak_before_restore_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, sys

app = Path("vsp_demo_app.py")
baks = sorted(Path(".").glob("vsp_demo_app.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
if not baks:
    print("[ERR] no backups found for vsp_demo_app.py")
    sys.exit(2)

good = None
for p in baks:
    try:
        py_compile.compile(str(p), doraise=True)
        good = p
        break
    except Exception:
        continue

if not good:
    print("[ERR] cannot find any compiling backup for vsp_demo_app.py")
    sys.exit(3)

app.write_text(good.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print("[OK] restored from:", good.name)
py_compile.compile(str(app), doraise=True)
print("[OK] py_compile OK (vsp_demo_app.py)")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] demoapp restored to latest compiling backup + restarted"
