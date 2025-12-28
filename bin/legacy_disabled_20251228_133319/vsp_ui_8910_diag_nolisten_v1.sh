#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== status =="
sudo systemctl --no-pager -l status vsp-ui-8910.service | sed -n '1,80p' || true

echo "== ss check =="
ss -ltnp | grep ':8910' || echo "[WARN] ss: no listener found"

echo "== curl retry (20 tries) =="
ok=0
for i in $(seq 1 20); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 1 http://127.0.0.1:8910/vsp5 2>/dev/null || echo FAIL)"
  echo "try#$i http_code=$code"
  if [ "$code" != "FAIL" ] && [ "$code" != "000" ]; then ok=1; break; fi
  sleep 0.3
done

echo "== main pid + state =="
MPID="$(systemctl show -p MainPID --value vsp-ui-8910.service 2>/dev/null || true)"
echo "MainPID=$MPID"
[ -n "${MPID:-}" ] && ps -o pid,ppid,stat,etime,%cpu,%mem,cmd -p "$MPID" || true

echo "== boot/error logs tail =="
echo "-- out_ci/ui_8910.boot.log (tail 200) --"
tail -n 200 out_ci/ui_8910.boot.log 2>/dev/null || true
echo "-- out_ci/ui_8910.error.log (tail 200) --"
tail -n 200 out_ci/ui_8910.error.log 2>/dev/null || true

echo "== journalctl (last 200) =="
sudo journalctl -u vsp-ui-8910.service --no-pager -n 200 || true

echo "== import check (timeout 6s) =="
timeout 6s /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3 - <<'PY' || echo "[FAIL] import timed out or crashed"
import time
t=time.time()
import wsgi_vsp_ui_gateway
print("import_ok seconds=", round(time.time()-t, 3))
app=getattr(wsgi_vsp_ui_gateway, "application", None)
print("application=", "OK" if app else "MISSING")
PY

if [ "$ok" = "1" ]; then
  echo "[OK] 8910 reachable now."
  curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -c 240; echo
else
  echo "[FAIL] 8910 still refused/unstable. The logs above contain the root cause."
fi
