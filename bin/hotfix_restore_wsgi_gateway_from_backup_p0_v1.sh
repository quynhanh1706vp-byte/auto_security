#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need ls; need head; need cp; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== find backups =="
CANDS="$(ls -1t "${F}".bak_* 2>/dev/null || true)"
[ -n "${CANDS:-}" ] || { echo "[ERR] no backups found for $F"; exit 3; }

GOOD=""
TMP="/tmp/_wsgi_vsp_ui_gateway_test.py"

echo "== probe backups by py_compile (newest first) =="
while IFS= read -r b; do
  cp -f "$b" "$TMP"
  if python3 -m py_compile "$TMP" >/dev/null 2>&1; then
    GOOD="$b"
    echo "[OK] good backup: $GOOD"
    break
  else
    echo "[SKIP] bad backup (py_compile fail): $b"
  fi
done <<< "$CANDS"

[ -n "${GOOD:-}" ] || { echo "[ERR] no compilable backup found"; exit 4; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_before_restore_${TS}"
echo "[BACKUP] ${F}.bak_before_restore_${TS}"

cp -f "$GOOD" "$F"
echo "[RESTORE] $F <= $GOOD"

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

echo "== restart 8910 clean =="
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_clean_p0_v2.sh

echo "== smoke =="
curl -sS -I http://127.0.0.1:8910/ | head -n 5 || true
curl -sS -I http://127.0.0.1:8910/runs | head -n 5 || true
