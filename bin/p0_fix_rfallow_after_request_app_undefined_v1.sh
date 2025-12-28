#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_fix_rfallow_attach_${TS}"
echo "[BACKUP] ${APP}.bak_fix_rfallow_attach_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

OPEN = "# ===================== VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V1 ====================="
CLOSE = "# ===================== /VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V1 ====================="

if OPEN not in s or CLOSE not in s:
    raise SystemExit("[ERR] marker block not found in vsp_demo_app.py")

pre, mid = s.split(OPEN, 1)
block, post = mid.split(CLOSE, 1)

# 1) remove decorator line '@app.after_request' if present
block2 = re.sub(r'^\s*@app\.after_request\s*\n', '', block, flags=re.M)

# 2) ensure the function exists (we assume it does). Add safe attach after function definition.
# Insert just before 'return resp' end? safer: append registration AFTER function block (end of our injected code)
attach = r'''
    # [VSP_P2] safe attach after_request (avoid NameError if app isn't ready)
    try:
        _a = None
        try:
            _a = app  # noqa: F821
        except Exception:
            _a = globals().get("application", None)
        if _a is not None and hasattr(_a, "after_request"):
            _a.after_request(_vsp_p2_rfallow_contract_after_request)
    except Exception:
        pass
'''
attach = "\n" + attach.strip("\n") + "\n"

# Only add once
if "safe attach after_request" not in block2:
    block2 = block2.rstrip() + attach

new_s = pre + OPEN + block2 + CLOSE + post
p.write_text(new_s, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile:", str(p))
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted $SVC (if present)"
