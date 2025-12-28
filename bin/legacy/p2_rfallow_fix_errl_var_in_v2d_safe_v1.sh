#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_fix_errl_${TS}"
echo "[BACKUP] ${APP}.bak_fix_errl_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

OPEN = "# ===================== VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2D_SAFE ====================="
CLOSE = "# ===================== /VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2D_SAFE ====================="
if OPEN not in s or CLOSE not in s:
    raise SystemExit("[ERR] V2D_SAFE block not found")

pre, mid = s.split(OPEN, 1)
blk, post = mid.split(CLOSE, 1)

# 1) Replace el -> err_l definition line if exists
blk2 = blk
blk2 = blk2.replace("el = err.lower()", "err_l = err.lower()")

# 2) Replace references "in el" -> "in err_l"
blk2 = re.sub(r'\bin\s+el\b', 'in err_l', blk2)

# 3) Ensure err_l exists (in case neither el nor err_l present)
if re.search(r'^\s*err_l\s*=\s*err\.lower\(\)\s*$', blk2, re.M) is None:
    # insert right after the err assignment line
    m = re.search(r'^\s*err\s*=\s*\(d\.get\("err".*\)\s*$', blk2, re.M)
    if not m:
        # fallback: after any line that assigns err =
        m = re.search(r'^\s*err\s*=\s*.*$', blk2, re.M)
    if not m:
        raise SystemExit("[ERR] cannot locate err= line in V2D_SAFE block to insert err_l")

    ins_at = m.end()
    blk2 = blk2[:ins_at] + "\n        err_l = err.lower()\n" + blk2[ins_at:]

# 4) Also ensure override line uses err_l (it already does in your file now)
# (no-op, but keep for safety)
blk2 = blk2.replace("('bad rid' in el)", "('bad rid' in err_l)")
blk2 = blk2.replace("('unknown rid' in el)", "('unknown rid' in err_l)")

s2 = pre + OPEN + blk2 + CLOSE + post
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched err_l in V2D_SAFE + py_compile")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted $SVC (if present)"
