#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
ELOG="out_ci/ui_8910.error.log"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sed; need grep; need ss; need tail; need date; need sudo; need systemctl

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== show top of $F (lines 1-40) =="
nl -ba "$F" | sed -n '1,40p'

echo
echo "== grep MARK/MARK_B lines =="
grep -nE '(^|[^A-Z0-9_])MARK(_B)?\b' "$F" | head -n 80 || true

echo
echo "== quick py_compile + import =="
python3 -m py_compile "$F" && echo "[OK] py_compile OK" || echo "[ERR] py_compile FAIL"
python3 - <<'PY' || true
import importlib, traceback
try:
    import wsgi_vsp_ui_gateway
    print("[OK] import wsgi_vsp_ui_gateway OK")
except Exception as e:
    print("[ERR] import failed:", repr(e))
    traceback.print_exc()
PY

echo
echo "== attempt auto-fix for MARK_B self-reference variants (if present) =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_diagfix_v7c_${TS}"
python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Replace any MARK_B assignment that references MARK_B on RHS AND uses isinstance(MARK, str) conditional
# Covers variants with spaces/comments/trailing stuff.
pat = re.compile(
    r'(?m)^(?P<ind>\s*)MARK_B\s*=\s*\(\s*MARK_B\s*if\s*isinstance\s*\(\s*MARK\s*,\s*str\s*\)\s*else\s*str\s*\(\s*MARK\s*\)\s*\.?encode\s*\(\s*\)\s*\)\s*(#.*)?$'
)
new = r"\g<ind>MARK_B = (MARK.encode('utf-8') if isinstance(MARK, str) else str(MARK).encode('utf-8'))"
s2, n = pat.subn(new, s)

# Paranoid: any MARK_B assignment line that contains "MARK_B if isinstance(MARK" anywhere
pat2 = re.compile(r'(?m)^(?P<ind>\s*)MARK_B\s*=.*MARK_B\s+if\s+isinstance\s*\(\s*MARK\s*,\s*str\s*\).*$', re.M)
s3, n2 = pat2.subn(new, s2)

if (n + n2) > 0:
    p.write_text(s3, encoding="utf-8")
    print(f"[OK] replaced MARK_B self-reference lines: {n+n2}")
else:
    print("[OK] no MARK_B self-reference pattern found (no change)")
PY

echo
echo "== re-py_compile after auto-fix =="
python3 -m py_compile "$F" && echo "[OK] py_compile OK"

echo
echo "== truncate error log (NEW only) =="
mkdir -p out_ci
sudo truncate -s 0 "$ELOG" || true

echo
echo "== restart service =="
sudo systemctl daemon-reload || true
sudo systemctl reset-failed "$SVC" || true
sudo systemctl restart "$SVC" || true
sleep 0.8

echo
echo "== ss listen :8910 =="
if ss -ltnp | grep -E ':8910\b' >/dev/null 2>&1; then
  ss -ltnp | grep -E ':8910\b' || true
  echo "[OK] LISTEN present"
  echo "== curl =="
  curl -m 2 -sS -I http://127.0.0.1:8910/ | sed -n '1,25p' || true
  exit 0
fi

echo "[FAIL] still not listening on 8910"
echo
echo "== systemd status =="
sudo systemctl --no-pager --full status "$SVC" | sed -n '1,160p' || true
echo
echo "== journal tail =="
sudo journalctl -u "$SVC" -n 220 --no-pager || true
echo
echo "== error log tail =="
tail -n 260 "$ELOG" 2>/dev/null || true

exit 3
