#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.broken_${TS}"
echo "[BROKEN_BACKUP] ${F}.broken_${TS}"

# ưu tiên backup mới nhất
CANDS=( $(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true) )
[ "${#CANDS[@]}" -gt 0 ] || { echo "[ERR] no backups found vsp_demo_app.py.bak_*"; exit 2; }

for b in "${CANDS[@]}"; do
  cp -f "$b" "${F}.cand"
  if python3 -m py_compile "${F}.cand" >/dev/null 2>&1; then
    cp -f "$b" "$F"
    rm -f "${F}.cand"
    echo "[OK] restored from: $b"
    python3 -m py_compile "$F"
    echo "[OK] py_compile OK (restored)"
    exit 0
  else
    echo "[SKIP] not compilable: $b"
  fi
done

echo "[ERR] no compilable backup found."
exit 3
