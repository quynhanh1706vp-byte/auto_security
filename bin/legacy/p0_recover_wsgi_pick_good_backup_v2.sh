#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need date; need head; need tail
command -v systemctl >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] current file quick check =="
if python3 -m py_compile "$WSGI" 2>/tmp/wsgi_compile_err.txt; then
  echo "[OK] current $WSGI compiles (no need recover)"
else
  echo "[WARN] current $WSGI does NOT compile:"
  tail -n 6 /tmp/wsgi_compile_err.txt || true
fi
echo

echo "== [1] scan backups newest->oldest, pick first py_compile OK =="
mapfile -t CANDS < <(ls -1t ${WSGI}.bak_* 2>/dev/null || true)
if [ "${#CANDS[@]}" -eq 0 ]; then
  echo "[ERR] no backups found: ${WSGI}.bak_*"
  exit 2
fi

PICK=""
for f in "${CANDS[@]}"; do
  # compile the backup file directly
  if python3 -m py_compile "$f" >/dev/null 2>&1; then
    PICK="$f"
    echo "[OK] found compile-ok backup: $PICK"
    break
  else
    echo "[skip] not compile-ok: $f"
  fi
done

if [ -z "${PICK:-}" ]; then
  echo "[ERR] no compile-ok backup found among ${#CANDS[@]} backups"
  echo "Tip: you may need a surgical removal of the broken inj block."
  exit 2
fi
echo

echo "== [2] restore =="
cp -f "$WSGI" "${WSGI}.broken_${TS}" 2>/dev/null || true
cp -f "$PICK" "$WSGI"
echo "[OK] restored $WSGI from $PICK (saved current as ${WSGI}.broken_${TS})"

python3 -m py_compile "$WSGI"
echo "[OK] restored $WSGI compiles"
echo

echo "== [3] restart service (needs sudo) =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  echo
  echo "== [4] status =="
  systemctl status "$SVC" --no-pager || true
  echo
  echo "== [5] last logs =="
  journalctl -u "$SVC" -n 120 --no-pager || true
else
  echo "[WARN] systemctl not available; restart the process manually"
fi

echo
echo "== [6] quick smoke (if up) =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS "$BASE/api/vsp/rid_latest" | python3 - <<'PY'
import json,sys
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "rid=", j.get("rid"))
PY
