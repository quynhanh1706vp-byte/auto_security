#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_except_${TS}"
echo "[BACKUP] ${F}.bak_fix_except_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

mark_end = "# END VSP_RUN_FILE_SAFE_ENDPOINT_P0_V1"
if mark_end not in s:
    print("[ERR] cannot find end marker:", mark_end)
    raise SystemExit(2)

# Remove ONLY the stray `except Exception: pass` that sits immediately before the END marker.
pat = r"\nexcept Exception:\n[ \t]+pass\n(?=\n# =========================\n# END VSP_RUN_FILE_SAFE_ENDPOINT_P0_V1)"
s2, n = re.subn(pat, "\n", s, count=1)

if n == 0:
    print("[WARN] no stray except-pass matched (maybe already fixed or different shape).")
else:
    print("[OK] removed stray except-pass before END marker")

p.write_text(s2, encoding="utf-8")
print("[OK] wrote:", p)
PY

echo "== show context around marker (sanity) =="
grep -n "VSP_RUN_FILE_SAFE_ENDPOINT_P0_V1" -n "$F" | head -n 3 || true
# show a few lines near the END marker
LN="$(grep -n "# END VSP_RUN_FILE_SAFE_ENDPOINT_P0_V1" "$F" | head -n1 | cut -d: -f1)"
if [ -n "${LN:-}" ]; then
  A=$((LN-12)); [ $A -lt 1 ] && A=1
  B=$((LN+6))
  nl -ba "$F" | sed -n "${A},${B}p"
fi

echo "== py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart 8910 =="
if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service | grep -q 'vsp-ui-8910.service'; then
  sudo systemctl restart vsp-ui-8910.service
  sudo systemctl --no-pager --full status vsp-ui-8910.service | sed -n '1,18p'
else
  echo "[INFO] systemd unit not found; use your restart script."
fi

echo "== smoke =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,12p'
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,15p'
