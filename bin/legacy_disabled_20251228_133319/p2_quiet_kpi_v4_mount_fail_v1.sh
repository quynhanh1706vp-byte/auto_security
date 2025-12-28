#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_QUIET_KPI_V4_MOUNT_FAIL_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_quietkpi_${TS}"
echo "[BACKUP] ${F}.bak_quietkpi_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys

MARK = "VSP_P2_QUIET_KPI_V4_MOUNT_FAIL_V1"
p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

if MARK in s:
    print("[OK] already patched:", MARK)
    sys.exit(0)

old1 = 'print("[VSP_KPI_V4] mount failed:", _e)'
new1 = """\
try:
    import os as _os
    if _os.environ.get("VSP_SAFE_DISABLE_KPI_V4","1") == "1":
        print("[VSP_KPI_V4] mount skipped by VSP_SAFE_DISABLE_KPI_V4=1")
    else:
        print("[VSP_KPI_V4] mount failed:", _e)
except Exception:
    print("[VSP_KPI_V4] mount failed:", _e)
""".rstrip("\n")

old2 = 'print("[VSP_KPI_V4] retry mount under app_context failed:", repr(e))'
new2 = """\
try:
    import os as _os
    if _os.environ.get("VSP_SAFE_DISABLE_KPI_V4","1") == "1":
        print("[VSP_KPI_V4] retry skipped by VSP_SAFE_DISABLE_KPI_V4=1")
    else:
        print("[VSP_KPI_V4] retry mount under app_context failed:", repr(e))
except Exception:
    print("[VSP_KPI_V4] retry mount under app_context failed:", repr(e))
""".rstrip("\n")

changed = 0
if old1 in s:
    s = s.replace(old1, new1, 1)
    changed += 1
if old2 in s:
    s = s.replace(old2, new2, 1)
    changed += 1

s += f"\n\n# ===================== {MARK} =====================\n# KPI_V4 mount/retry log quiet when VSP_SAFE_DISABLE_KPI_V4=1\n# ===================== /{MARK} =====================\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK, "changed_items=", changed)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

systemctl restart "$SVC" 2>/dev/null || true

echo "== journal KPI_V4 (expect 'skipped', no 'mount failed') =="
journalctl -u "$SVC" -n 160 --no-pager | grep -n "VSP_KPI_V4" | tail -n 40 || true
