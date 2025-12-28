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
cp -f "$APP" "${APP}.bak_bad_rid_override404_${TS}"
echo "[BACKUP] ${APP}.bak_bad_rid_override404_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

candidates = [
    ("# ===================== VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2D_SAFE =====================",
     "# ===================== /VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2D_SAFE ====================="),
    ("# ===================== VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2_SAFE =====================",
     "# ===================== /VSP_P2_RFALLOW_CONTRACT_AFTER_REQUEST_V2_SAFE ====================="),
]

found = False
for OPEN, CLOSE in candidates:
    if OPEN in s and CLOSE in s:
        pre, mid = s.split(OPEN, 1)
        blk, post = mid.split(CLOSE, 1)

        if "bad rid" in blk.lower() and "http = 404" in blk:
            print("[OK] override already present in block; skip")
            found = True
            break

        # insert right before: d['http'] = int(http)  (or d["http"])
        pat = r'(\n\s*d\[(?:\'|")http(?:\'|")\]\s*=\s*int\(http\)\s*\n)'
        m = re.search(pat, blk)
        if not m:
            raise SystemExit(f"[ERR] cannot find d['http']=int(http) inside {OPEN}")

        insert = (
            "\n        # [P2] override semantic http for missing RID\n"
            "        if ('bad rid' in err_l) or ('unknown rid' in err_l):\n"
            "            http = 404\n"
        )

        blk2 = blk[:m.start()] + insert + blk[m.start():]
        s = pre + OPEN + blk2 + CLOSE + post
        found = True
        print(f"[OK] inserted bad-rid override into block: {OPEN}")
        break

if not found:
    raise SystemExit("[ERR] cannot find any VSP_P2_RFALLOW_CONTRACT block (V2D_SAFE/V2_SAFE) in vsp_demo_app.py")

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile after patch")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted $SVC (if present)"
