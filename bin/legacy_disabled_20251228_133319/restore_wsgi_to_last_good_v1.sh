#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== try restore last good backup (newest-first) =="

# candidates: any .bak_* of wsgi
mapfile -t CANDS < <(ls -1t wsgi_vsp_ui_gateway.py.bak_* 2>/dev/null || true)
[ ${#CANDS[@]} -gt 0 ] || { echo "[ERR] no backups found (wsgi_vsp_ui_gateway.py.bak_*)"; exit 3; }

for B in "${CANDS[@]}"; do
  cp -f "$B" "$F"
  if python3 -m py_compile "$F" >/dev/null 2>&1; then
    echo "[OK] restored last good => $B"
    python3 -m py_compile "$F"
    exit 0
  else
    echo "[SKIP] not compiling => $B"
  fi
done

echo "[ERR] no compiling backup found"
exit 4
