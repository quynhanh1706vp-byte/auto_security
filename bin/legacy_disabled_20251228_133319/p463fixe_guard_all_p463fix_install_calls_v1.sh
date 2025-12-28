#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p463fixe_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl; need grep; need head
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

MARK="VSP_P463FIXE_GUARD_ALL_P463FIX_INSTALL_CALLS_V1"
if MARK in s:
    print("[OK] already patched P463fixe")
    sys.exit(0)

if "_vsp_p463fix_install" not in s:
    print("[OK] no _vsp_p463fix_install symbol found; nothing to do")
    sys.exit(0)

guard_fn = r'''
# --- VSP_P463FIXE_GUARD_ALL_P463FIX_INSTALL_CALLS_V1 ---
def _vsp_p463fix_install_guarded():
    try:
        _a = globals().get("app", None)
        if _a is not None and hasattr(_a, "add_url_rule"):
            return _vsp_p463fix_install()
    except Exception:
        return None
    return None
# --- /VSP_P463FIXE_GUARD_ALL_P463FIX_INSTALL_CALLS_V1 ---
'''.strip("\n")

# Insert guard right after the definition of _vsp_p463fix_install if possible
m = re.search(r"(?s)(^\s*def\s+_vsp_p463fix_install\s*\(.*?\)\s*:\s*\n.*?)(?=^\s*def\s|\Z)", s, re.M)
if m:
    insert_at = m.end(1)
    s = s[:insert_at] + "\n\n" + guard_fn + "\n\n" + s[insert_at:]
else:
    # fallback: append near end
    s = s.rstrip() + "\n\n" + guard_fn + "\n"

# Replace ALL calls `_vsp_p463fix_install()` with guarded version, but NOT the def line
# (safe even if used as a statement/expression)
def_pat = re.compile(r"(?m)^\s*def\s+_vsp_p463fix_install\s*\(")
call_pat = re.compile(r"\b_vsp_p463fix_install\s*\(\s*\)")

out_lines=[]
for ln in s.splitlines(True):
    if def_pat.search(ln):
        out_lines.append(ln)
        continue
    if "_vsp_p463fix_install(" in ln:
        ln = call_pat.sub("_vsp_p463fix_install_guarded()", ln)
    out_lines.append(ln)

s2="".join(out_lines)
p.write_text(s2, encoding="utf-8")
print("[OK] patched: replaced _vsp_p463fix_install() calls with guarded wrapper")
PY

python3 -m py_compile "$W" | tee -a "$OUT/log.txt"

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" || true
sleep 1
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true

echo "== quick export re-check ==" | tee -a "$OUT/log.txt"
curl -sS --connect-timeout 1 --max-time 10 "$BASE/api/vsp/sha256" | head -c 220 | tee -a "$OUT/log.txt"
echo "" | tee -a "$OUT/log.txt"

echo "== tail error log (should stay clean) ==" | tee -a "$OUT/log.txt"
tail -n 60 out_ci/ui_8910.error.log 2>/dev/null | tee "$OUT/error_tail.txt" || true

echo "[OK] DONE: $OUT/log.txt" | tee -a "$OUT/log.txt"
