#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== precheck: py_compile =="
python3 -m py_compile vsp_demo_app.py wsgi_vsp_ui_gateway.py 2>/dev/null || {
  echo "[ERR] py_compile failed. Show errors:"
  python3 -m py_compile vsp_demo_app.py wsgi_vsp_ui_gateway.py
  exit 2
}

echo "== stop listeners 8910 =="
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true

echo "== restart systemd =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 0.6

echo "== wait for :8910 (max ~4s) =="
ok=0
for i in 1 2 3 4 5 6 7 8; do
  if ss -ltnp 2>/dev/null | grep -q ':8910'; then ok=1; break; fi
  sleep 0.5
done

if [ "$ok" -ne 1 ]; then
  echo "[ERR] 8910 not listening"
  echo "== systemctl status =="
  sudo systemctl status vsp-ui-8910.service --no-pager || true
  echo "== journal tail =="
  sudo journalctl -u vsp-ui-8910.service -n 200 --no-pager || true
  echo "== boot log tail (if exists) =="
  tail -n 200 out_ci/ui_8910.boot.log 2>/dev/null || true
  exit 2
fi

echo "[OK] 8910 is listening"
echo "== quick HTTP =="
curl -sS -I "$BASE/vsp5" | sed -n '1,12p' || true
curl -sS "$BASE/api/vsp/runs?limit=1" | head -c 200; echo
