#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p463fixg_${TS}"
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
import sys, re

p=Path("wsgi_vsp_ui_gateway.py")
lines=p.read_text(encoding="utf-8", errors="replace").splitlines(True)

MARK="VSP_P463FIXG_GUARD_INSIDE_P463FIX_INSTALL_V1"
txt="".join(lines)
if MARK in txt:
    print("[OK] already patched P463fixg")
    sys.exit(0)

# find function def line
idx=None
def_re=re.compile(r'^(\s*)def\s+_vsp_p463fix_install\s*\(.*\)\s*:\s*$')
for i,ln in enumerate(lines):
    if def_re.match(ln):
        idx=i
        indent=def_re.match(ln).group(1)
        break

if idx is None:
    print("[ERR] cannot find def _vsp_p463fix_install(...)")
    sys.exit(2)

# insert guard right after def line (before any existing body)
body_indent = indent + "    "
guard = [
    f"{body_indent}# --- {MARK} ---\n",
    f"{body_indent}try:\n",
    f"{body_indent}    _a = globals().get('app', None)\n",
    f"{body_indent}    if _a is None or not hasattr(_a, 'add_url_rule'):\n",
    f"{body_indent}        return None\n",
    f"{body_indent}    app = _a  # force real Flask app only\n",
    f"{body_indent}except Exception:\n",
    f"{body_indent}    return None\n",
    f"{body_indent}# --- /{MARK} ---\n",
]

# avoid inserting twice if function already starts with a similar guard
# check next ~25 lines for our marker (already handled) or 'add_url_rule' guard
lookahead = "".join(lines[idx+1:idx+30])
if "hasattr(_a, 'add_url_rule')" in lookahead or MARK in lookahead:
    print("[OK] function already guarded (looks like); skipping")
    sys.exit(0)

lines[idx+1:idx+1] = guard
p.write_text("".join(lines), encoding="utf-8")
print("[OK] inserted guard inside _vsp_p463fix_install()")
PY

python3 -m py_compile "$W" | tee -a "$OUT/log.txt"

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" || true
sleep 1
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true

echo "== check crash signature (should be empty) ==" | tee -a "$OUT/log.txt"
tail -n 220 out_ci/ui_8910.error.log | grep -n "AttributeError: .*add_url_rule\|_vsp_p463fix_install" || true

echo "[OK] P463fixg done: $OUT/log.txt" | tee -a "$OUT/log.txt"
