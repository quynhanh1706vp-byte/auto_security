#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"

usage(){ echo "Usage: $0 on|off|status"; exit 2; }
act="${1:-}"; [ -n "$act" ] || usage

_manager_env(){
  sudo systemctl show-environment 2>/dev/null | grep -n "VSP_KPI_V4_LOG" || echo "(VSP_KPI_V4_LOG not set)"
}

_status(){
  echo "== manager env =="
  _manager_env

  # only check NEW log bytes
  before=0
  if [ -f "$ERRLOG" ]; then before="$(stat -c%s "$ERRLOG" 2>/dev/null || echo 0)"; fi
  echo "[INFO] errlog_size_before=$before"

  # trigger a request (this is what would emit KPI_V4 if ON)
  curl -sS "$BASE/vsp5" >/dev/null 2>&1 || true
  sleep 0.4

  if [ ! -f "$ERRLOG" ]; then
    echo "(missing $ERRLOG)"
    return 0
  fi

  after="$(stat -c%s "$ERRLOG" 2>/dev/null || echo 0)"
  echo "[INFO] errlog_size_after=$after"

  if [ "$after" -le "$before" ]; then
    echo "[OK] no new error-log bytes"
    return 0
  fi

  tmp="$(mktemp /tmp/kpi_v4_new_XXXXXX.txt)"
  tail -c +"$((before+1))" "$ERRLOG" > "$tmp" || true

  echo "== NEW KPI_V4 lines (if any) =="
  grep -n "VSP_KPI_V4" "$tmp" || echo "[OK] KPI_V4 silent in NEW part"
}

case "$act" in
  on)
    sudo systemctl set-environment VSP_KPI_V4_LOG=1
    sudo systemctl restart "$SVC"
    _status
    ;;
  off)
    sudo systemctl unset-environment VSP_KPI_V4_LOG
    sudo systemctl restart "$SVC"
    _status
    ;;
  status)
    _status
    ;;
  *)
    usage
    ;;
esac
