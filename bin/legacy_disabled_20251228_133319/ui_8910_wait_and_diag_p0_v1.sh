#!/usr/bin/env bash
set -euo pipefail

PORT=8910
HOST=127.0.0.1
BASE="http://${HOST}:${PORT}"
SVC="vsp-ui-8910.service"
UI="/home/test/Data/SECURITY_BUNDLE/ui"
ERR="${UI}/out_ci/ui_8910.error.log"
ACC="${UI}/out_ci/ui_8910.access.log"
BOOT="${UI}/out_ci/ui_8910.boot.log"

echo "== wait LISTEN ${HOST}:${PORT} (max ~6s) =="
ok=0
for i in $(seq 1 30); do
  if ss -ltnp 2>/dev/null | grep -q "${HOST}:${PORT}"; then
    ok=1
    echo "[OK] LISTEN detected at try=$i"
    break
  fi
  sleep 0.2
done

echo "== smoke curl (retry max ~6s) =="
for i in $(seq 1 30); do
  if curl -sS -I "${BASE}/" >/tmp/ui_8910_hdr.$$ 2>/tmp/ui_8910_curlerr.$$; then
    echo "[OK] curl / succeeded at try=$i"
    sed -n '1,12p' /tmp/ui_8910_hdr.$$ || true
    rm -f /tmp/ui_8910_hdr.$$ /tmp/ui_8910_curlerr.$$ || true
    exit 0
  fi
  sleep 0.2
done

echo "[FAIL] still cannot connect after retries"
echo "== ss -ltnp | grep :${PORT} =="
ss -ltnp | grep ":${PORT}" || true

echo "== systemctl status (top) =="
sudo systemctl --no-pager --full status "${SVC}" | sed -n '1,80p' || true

echo "== journalctl -u ${SVC} (last 120 lines) =="
sudo journalctl -u "${SVC}" -n 120 --no-pager || true

echo "== tail error log =="
test -f "${ERR}" && tail -n 120 "${ERR}" || echo "[WARN] missing ${ERR}"

echo "== tail boot log (if any) =="
test -f "${BOOT}" && tail -n 120 "${BOOT}" || echo "[WARN] missing ${BOOT}"

echo "== tail access log =="
test -f "${ACC}" && tail -n 60 "${ACC}" || echo "[WARN] missing ${ACC}"

exit 2
