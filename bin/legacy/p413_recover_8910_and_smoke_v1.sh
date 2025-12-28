#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need journalctl; need ss; need awk; need grep; need curl; need ls; need head; need date

echo "== [P413] recover service + smoke =="
echo "[INFO] svc=$SVC base=$BASE"

status_short(){
  systemctl is-active "$SVC" 2>/dev/null || true
}

show_diag(){
  echo ""
  echo "== [DIAG] systemctl status =="
  sudo systemctl status "$SVC" --no-pager -l || true
  echo ""
  echo "== [DIAG] last logs (200 lines) =="
  sudo journalctl -u "$SVC" -n 200 --no-pager || true
  echo ""
  echo "== [DIAG] listen 8910 =="
  ss -lntp | awk '$4 ~ /:8910$/ {print}' || true
}

wait_up(){
  local tries="${1:-40}"
  for i in $(seq 1 "$tries"); do
    if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1; then
      echo "[OK] UI up at $BASE (try#$i)"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

restart_once(){
  echo ""
  echo "== [STEP] restart $SVC =="
  sudo systemctl daemon-reload || true
  sudo systemctl restart "$SVC" || true
  sleep 0.8
  echo "[INFO] is-active=$(status_short)"
}

echo "[INFO] initial is-active=$(status_short)"
restart_once

if wait_up 50; then
  echo ""
  echo "== [STEP] run smoke P410 =="
  bash bin/p410_smoke_no_legacy_10x_v1.sh
  exit 0
fi

echo ""
echo "[WARN] UI still down after restart. Collecting diagnostics..."
show_diag

# Auto rollback P412 if backup exists (latest one)
BK="$(ls -1t ${APP}.bak_p412_* 2>/dev/null | head -n1 || true)"
if [ -n "${BK:-}" ]; then
  echo ""
  echo "== [ROLLBACK] restoring $BK -> $APP =="
  cp -f "$BK" "$APP"
  python3 -m py_compile "$APP" && echo "[OK] py_compile after rollback OK" || true

  restart_once
  if wait_up 60; then
    echo ""
    echo "== [STEP] run smoke P410 (after rollback) =="
    bash bin/p410_smoke_no_legacy_10x_v1.sh || true
    echo ""
    echo "[INFO] Service recovered after rollback. (P412 likely triggered runtime issue in your service wiring.)"
    exit 0
  fi
fi

echo ""
echo "[FAIL] UI still down. Please check the diagnostics above (status + journal)."
exit 3
