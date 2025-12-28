#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

WSGI="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
VER="cio_${TS}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need head; need curl

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

echo "== [0] Backup WSGI =="
cp -f "$WSGI" "${WSGI}.bak_sync_ciover_${TS}"
echo "[BACKUP] ${WSGI}.bak_sync_ciover_${TS}"

echo "== [1] Replace cio_* ver everywhere (templates + WSGI) => $VER =="
python3 - <<PY
from pathlib import Path
import re, sys

ver="${VER}"

def bump_text(s: str) -> str:
    # CSS
    s = re.sub(r'(vsp_cio_shell_v1\.css\?v=)cio_[0-9_]+', r'\\1'+ver, s)
    # JS
    s = re.sub(r'(vsp_cio_shell_apply_v1\.js\?v=)cio_[0-9_]+', r'\\1'+ver, s)
    return s

patched=0
# templates
root=Path("templates")
for f in root.rglob("*.html"):
    s=f.read_text(encoding="utf-8", errors="replace")
    s2=bump_text(s)
    if s2!=s:
        f.write_text(s2, encoding="utf-8")
        patched += 1

# wsgi
w=Path("${WSGI}")
ws=w.read_text(encoding="utf-8", errors="replace")
ws2=bump_text(ws)
if ws2!=ws:
    w.write_text(ws2, encoding="utf-8")
    patched += 1

print("[OK] files_patched=", patched, "ver=", ver)
PY

echo "== [2] py_compile WSGI =="
python3 -m py_compile "$WSGI"
echo "[OK] py_compile ok"

echo "== [3] Restart =="
if command -v systemctl >/dev/null 2>&1; then
  (sudo systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted $SVC") || echo "[WARN] restart failed or svc not found: $SVC"
fi

echo "== [4] Smoke: /vsp5 must show NEW ver =="
curl -fsS --max-time 3 --range 0-120000 "$BASE/vsp5" | grep -n "vsp_cio_shell_v1.css\\|vsp_cio_shell_apply_v1.js" | head -n 20 || true
echo "[INFO] expected ver: $VER"
