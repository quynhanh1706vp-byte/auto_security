#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p463fixd_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl; need awk; need head
command -v sudo >/dev/null 2>&1 || { echo "[ERR] need sudo" | tee -a "$OUT/log.txt"; exit 2; }
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl" | tee -a "$OUT/log.txt"; exit 2; }

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$W" "$OUT/${W}.bak_${TS}"
echo "[OK] backup => $OUT/${W}.bak_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P463FIXD_GUARD_P463FIX_INSTALL_CALL_V1"
if MARK in s:
    print("[OK] already patched P463fixd")
    sys.exit(0)

# Replace the bare call line: _vsp_p463fix_install()
pat = re.compile(r'(?m)^\s*_vsp_p463fix_install\(\)\s*$')

guard = r'''
# --- VSP_P463FIXD_GUARD_P463FIX_INSTALL_CALL_V1 ---
try:
    _a = globals().get("app", None)
    # only run if it's a real Flask app (has add_url_rule)
    if _a is not None and hasattr(_a, "add_url_rule"):
        _vsp_p463fix_install()
except Exception:
    pass
# --- /VSP_P463FIXD_GUARD_P463FIX_INSTALL_CALL_V1 ---
'''.strip("\n")

if not pat.search(s):
    print("[WARN] cannot find bare call _vsp_p463fix_install() to patch; skipping")
    # still stamp marker to avoid repeated attempts? no, exit nonzero for visibility
    sys.exit(2)

s2 = pat.sub(guard, s, count=1)
p.write_text(s2, encoding="utf-8")
print("[OK] patched guard around _vsp_p463fix_install() call")
PY

python3 -m py_compile "$W" | tee -a "$OUT/log.txt"

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" || true
sleep 1
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true

echo "== quick export re-check ==" | tee -a "$OUT/log.txt"
curl -sS --connect-timeout 1 --max-time 10 "$BASE/api/vsp/sha256" | head -c 220 | tee -a "$OUT/log.txt"
echo "" | tee -a "$OUT/log.txt"
curl -sS -D- -o /dev/null --connect-timeout 1 --max-time 10 "$BASE/api/vsp/export_csv" \
 | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:/{print}' | tee -a "$OUT/log.txt"
curl -sS -D- -o /dev/null --connect-timeout 1 --max-time 10 "$BASE/api/vsp/export_tgz" \
 | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:/{print}' | tee -a "$OUT/log.txt"

echo "== tail error log (should NOT show AttributeError add_url_rule) ==" | tee -a "$OUT/log.txt"
tail -n 40 out_ci/ui_8910.error.log 2>/dev/null | tee "$OUT/error_tail.txt" || true

echo "[OK] DONE: $OUT/log.txt" | tee -a "$OUT/log.txt"
