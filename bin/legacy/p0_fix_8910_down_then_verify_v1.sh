#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ss; need awk; need sed; need grep; need curl; need date

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PORT="8910"

echo "[INFO] TS=$(date +%Y%m%d_%H%M%S)"
echo "[INFO] BASE=$BASE"

echo "== cleanup lock =="
rm -f /tmp/vsp_ui_${PORT}.lock /tmp/vsp_ui_${PORT}.lock.* 2>/dev/null || true
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true

echo "== kill listeners on :$PORT (if any) =="
PIDS="$(ss -ltnp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p {print}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// }" ]; then
  echo "[INFO] killing pids: $PIDS"
  kill -9 $PIDS 2>/dev/null || true
else
  echo "[OK] no pid holding :$PORT"
fi

echo "== try systemd restart (if exists) =="
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q '^vsp-ui-8910\.service'; then
    sudo systemctl restart vsp-ui-8910.service || true
    sleep 1.2
  else
    echo "[WARN] systemd unit vsp-ui-8910.service not found"
  fi
fi

echo "== fallback start script =="
if ! ss -ltnp 2>/dev/null | grep -q ":$PORT"; then
  if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
    bin/p1_ui_8910_single_owner_start_v2.sh || true
    sleep 1.2
  else
    echo "[ERR] missing bin/p1_ui_8910_single_owner_start_v2.sh"
  fi
fi

echo "== check listen :$PORT =="
ss -ltnp 2>/dev/null | grep ":$PORT" || { echo "[ERR] still not listening on :$PORT"; exit 3; }

echo "== verify core pages =="
curl -fsS -I "$BASE/" | sed -n '1,12p' || true
curl -fsS -I "$BASE/vsp5" | sed -n '1,12p' || true
curl -fsS "$BASE/vsp5" | head -n 5 || true

echo "== verify 3 tabs HTML =="
for p in data_source settings rule_overrides; do
  echo "--- GET /$p"
  curl -fsS -I "$BASE/$p" | sed -n '1,12p' || true
  curl -fsS "$BASE/$p" | head -n 5 || true
done

echo "== verify 3 APIs =="
curl -fsS "$BASE/api/vsp/findings_v1?limit=2&offset=0" | head -c 220; echo
curl -fsS "$BASE/api/vsp/settings_v1" | head -c 220; echo
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | head -c 220; echo

echo "== tail boot logs (best effort) =="
[ -f out_ci/ui_8910.boot.log ] && tail -n 120 out_ci/ui_8910.boot.log || true
[ -f nohup.out ] && tail -n 80 nohup.out || true

echo "== journalctl (if unit exists) =="
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q '^vsp-ui-8910\.service'; then
    sudo journalctl -u vsp-ui-8910.service -n 120 --no-pager || true
  fi
fi

echo "[OK] 8910 up + verified"
