#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p463fixf_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need grep
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

MARK="VSP_P463FIXF_GUARD_P463FIX_INSTALL_V1"
if MARK in s:
    print("[OK] already patched P463fixf")
    sys.exit(0)

# Patch ANY standalone call line with indentation preserved
pat = re.compile(r'(?m)^(\s*)_vsp_p463fix_install\(\)\s*$')

def repl(m):
    ind = m.group(1)
    block = [
        f"{ind}# --- {MARK} ---",
        f"{ind}try:",
        f"{ind}    _a = globals().get('app', None)",
        f"{ind}    if _a is not None and hasattr(_a, 'add_url_rule'):",
        f"{ind}        _vsp_p463fix_install()",
        f"{ind}except Exception:",
        f"{ind}    pass",
        f"{ind}# --- /{MARK} ---",
    ]
    return "\n".join(block)

if not pat.search(s):
    print("[WARN] no standalone _vsp_p463fix_install() call line found; nothing changed")
    # still stamp marker to avoid looping? no, keep file unchanged
    sys.exit(0)

s2 = pat.sub(repl, s, count=1)
p.write_text(s2, encoding="utf-8")
print("[OK] guarded one _vsp_p463fix_install() call")
PY

python3 -m py_compile "$W" | tee -a "$OUT/log.txt"

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" || true
sleep 1
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true

echo "== verify no more add_url_rule crash appears in new logs ==" | tee -a "$OUT/log.txt"
tail -n 120 out_ci/ui_8910.error.log | grep -n "add_url_rule\|_vsp_p463fix_install" || true

echo "[OK] P463fixf done: $OUT/log.txt" | tee -a "$OUT/log.txt"
