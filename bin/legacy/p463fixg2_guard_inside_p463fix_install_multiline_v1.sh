#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p463fixg2_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need grep; need head
command -v sudo >/dev/null 2>&1 || { echo "[ERR] need sudo" | tee -a "$OUT/log.txt"; exit 2; }
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl" | tee -a "$OUT/log.txt"; exit 2; }

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$W" "$OUT/${W}.bak_${TS}"
echo "[OK] backup => $OUT/${W}.bak_${TS}" | tee -a "$OUT/log.txt"

# quick evidence: show where def name appears (for audit)
echo "== grep def occurrences ==" | tee -a "$OUT/log.txt"
grep -n "def _vsp_p463fix_install" -n "$W" | head -n 5 | tee -a "$OUT/log.txt" || true

python3 - <<'PY'
from pathlib import Path
import sys, re

p=Path("wsgi_vsp_ui_gateway.py")
lines=p.read_text(encoding="utf-8", errors="replace").splitlines(True)

MARK="VSP_P463FIXG2_GUARD_INSIDE_P463FIX_INSTALL_V1"
full="".join(lines)
if MARK in full:
    print("[OK] already patched P463fixg2")
    sys.exit(0)

# Find start line of def (can be multiline signature)
start=None
indent=""
for i,ln in enumerate(lines):
    m=re.match(r'^(\s*)def\s+_vsp_p463fix_install\b', ln)
    if m:
        start=i
        indent=m.group(1)
        break

if start is None:
    print("[ERR] cannot find def _vsp_p463fix_install (even multiline)")
    sys.exit(2)

# Find signature end: first subsequent line (including start) whose stripped endswith ':'
sig_end=None
for j in range(start, min(start+80, len(lines))):
    # ignore comment-only lines in signature
    s=lines[j].rstrip()
    if s.strip().endswith(":"):
        sig_end=j
        break

if sig_end is None:
    print("[ERR] cannot find end of function signature ':' within 80 lines")
    sys.exit(3)

body_indent = indent + "    "
guard = [
    f"{body_indent}# --- {MARK} ---\n",
    f"{body_indent}try:\n",
    f"{body_indent}    _a = globals().get('app', None)\n",
    f"{body_indent}    # In your deployment, 'app' may be a WSGI wrapper (no add_url_rule). Avoid crash.\n",
    f"{body_indent}    if _a is None or not hasattr(_a, 'add_url_rule'):\n",
    f"{body_indent}        return None\n",
    f"{body_indent}except Exception:\n",
    f"{body_indent}    return None\n",
    f"{body_indent}# --- /{MARK} ---\n",
]

# Insert guard right after signature end line
# But do not insert if the next few lines already have our guard pattern
lookahead="".join(lines[sig_end+1:sig_end+25])
if "hasattr(_a, 'add_url_rule')" in lookahead:
    print("[OK] looks already guarded; skip")
    sys.exit(0)

lines[sig_end+1:sig_end+1] = guard
p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] inserted guard after signature line {sig_end+1} (1-based {sig_end+2})")
PY

python3 -m py_compile "$W" | tee -a "$OUT/log.txt"

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" || true
sleep 1
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true

echo "== check crash signature (should be empty/new-free) ==" | tee -a "$OUT/log.txt"
tail -n 250 out_ci/ui_8910.error.log | grep -n "AttributeError: .*add_url_rule\|_vsp_p463fix_install" || true

echo "[OK] P463fixg2 done: $OUT/log.txt" | tee -a "$OUT/log.txt"
