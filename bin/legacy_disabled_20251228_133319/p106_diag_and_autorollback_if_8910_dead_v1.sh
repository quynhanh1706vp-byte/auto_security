#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
OUT="out_ci"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p106_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need sudo; need ss; need curl; need tail; need head; need grep; need date; need python3

echo "== [P106] snapshot =="
systemctl show -p ActiveState,SubState,MainPID,ExecStart,DropInPaths "$SVC" | sed 's/; /\n/g' > "$EVID/show.txt" || true
systemctl status "$SVC" --no-pager -n 80 > "$EVID/status.txt" || true
journalctl -u "$SVC" -n 200 --no-pager > "$EVID/journal_200.txt" || true
ss -lntp > "$EVID/ss.txt" || true

echo "[OK] saved $EVID/show.txt $EVID/status.txt $EVID/journal_200.txt $EVID/ss.txt"

echo "== [P106] restart + wait LISTEN 8910 =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" --quiet || { echo "[ERR] service not active"; exit 2; }

ok_listen=0
for i in $(seq 1 80); do
  if ss -lntp 2>/dev/null | grep -qE ':(8910)\b'; then ok_listen=1; break; fi
  sleep 0.1
done

if [ "$ok_listen" -ne 1 ]; then
  echo "[FAIL] no LISTEN on 8910 after restart"
  systemctl status "$SVC" --no-pager -n 120 | tee "$EVID/status_after.txt" || true
  journalctl -u "$SVC" -n 200 --no-pager | tee "$EVID/journal_after.txt" || true
  echo "[INFO] Will try import-test gateway + rollback P105 if needed..."
else
  echo "[OK] LISTEN 8910 detected"
fi

echo "== [P106] import test gateway (detect crash) =="
PYBIN="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"
if [ ! -x "$PYBIN" ]; then PYBIN="$(command -v python3)"; fi

set +e
"$PYBIN" - <<'PY' >"$EVID/import_test.txt" 2>&1
import importlib, sys
m = importlib.import_module("wsgi_vsp_ui_gateway")
print("IMPORT_OK", getattr(m, "__file__", None))
print("HAS_application", hasattr(m, "application"))
PY
rc=$?
set -e
echo "[import_rc]=$rc"
tail -n 40 "$EVID/import_test.txt" || true

# If import failed OR 8910 not listening OR HTTP not reachable -> rollback latest bak_p105
need_rollback=0
if [ "$rc" -ne 0 ]; then need_rollback=1; fi

# quick HTTP probe (even if listen ok)
set +e
curl -fsS --connect-timeout 1 --max-time 2 "$BASE/runs" -o /dev/null
http_rc=$?
set -e
echo "[http_rc]=$http_rc"
if [ "$http_rc" -ne 0 ]; then need_rollback=1; fi

if [ "$need_rollback" -eq 1 ]; then
  echo "== [P106] ROLLBACK: restore newest $W.bak_p105_* =="
  BAK="$(ls -1t ${W}.bak_p105_* 2>/dev/null | head -n 1 || true)"
  if [ -z "${BAK:-}" ]; then
    echo "[ERR] no backup ${W}.bak_p105_* found"
    echo "[HINT] check backups: ls -1t ${W}.bak_* | head"
    exit 2
  fi
  echo "[INFO] restore from: $BAK"
  cp -f "$BAK" "$W"

  echo "== [P106] restart after rollback =="
  sudo systemctl restart "$SVC"
  sudo systemctl is-active "$SVC" --quiet || { echo "[ERR] service not active after rollback"; exit 2; }

  # wait http
  ok=0
  for i in $(seq 1 120); do
    if curl -fsS --connect-timeout 1 --max-time 3 "$BASE/runs" -o /dev/null; then ok=1; break; fi
    sleep 0.2
  done
  [ "$ok" -eq 1 ] || { echo "[ERR] still not reachable after rollback"; journalctl -u "$SVC" -n 120 --no-pager | tail -n 120; exit 2; }
  echo "[OK] service recovered after rollback"
else
  echo "[OK] service seems healthy; no rollback needed"
fi

echo "[OK] P106 done. Evidence: $EVID"
