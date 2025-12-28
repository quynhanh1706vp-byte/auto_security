#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="vsp-ui-8910.service"
LOG="out_ci/ui_8910.error.log"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need sudo; need systemctl; need ss; need grep; need sed; need date; need curl; need awk; need readlink

echo "== restart + wait for bind =="
sudo systemctl daemon-reload || true
sudo systemctl reset-failed "$SVC" || true
sudo systemctl restart "$SVC" || true

# Poll up to 6s: status + listen
for i in 1 2 3 4 5 6 7 8; do
  echo "-- poll $i --"
  sudo systemctl show "$SVC" -p ActiveState -p SubState -p MainPID --no-pager
  PID="$(sudo systemctl show "$SVC" -p MainPID --value --no-pager || true)"
  if [ -n "${PID:-}" ] && [ "$PID" != "0" ] && sudo test -d "/proc/$PID"; then
    echo "[PID]=$PID exists"
  else
    echo "[PID]=$PID (missing or 0)"
  fi

  # Always use sudo ss to avoid any permission quirks
  if sudo ss -ltnp | grep -E ':8910\b' >/dev/null 2>&1; then
    echo "[OK] LISTEN found:"
    sudo ss -ltnp | grep -E ':8910\b' || true
    break
  else
    echo "[WAIT] no LISTEN yet"
  fi
  sleep 0.8
done

echo
echo "== final ss check =="
sudo ss -ltnp | grep -E ':8910\b' || echo "[FAIL] still no LISTEN on 8910"

echo
echo "== curl (2s) =="
curl -m 2 -sS -I http://127.0.0.1:8910/ | sed -n '1,25p' || echo "[curl] FAIL"

echo
echo "== unit (relevant lines) =="
sudo awk 'BEGIN{p=0} /^\[Service\]/{p=1} /^\[/{if($0!="[Service]")p=0} {if(p)print NR ":" $0}' /etc/systemd/system/vsp-ui-8910.service | sed -n '1,220p' || true

echo
echo "== journal since 2 minutes ago =="
sudo journalctl -u "$SVC" --since "-2 min" --no-pager | tail -n 260 || true

echo
echo "== error log tail =="
tail -n 260 "$LOG" 2>/dev/null || echo "[INFO] no $LOG yet"

echo
echo "== if PID exists: check netns + cmdline =="
PID="$(sudo systemctl show "$SVC" -p MainPID --value --no-pager || true)"
if [ -n "${PID:-}" ] && [ "$PID" != "0" ] && sudo test -d "/proc/$PID"; then
  echo "[PID]=$PID"
  echo "cmdline:"
  sudo tr '\0' ' ' < "/proc/$PID/cmdline" | sed 's/  */ /g' | sed -n '1,2p' || true
  echo "netns:"
  echo "  pid1: $(readlink /proc/1/ns/net)"
  echo "  svc : $(readlink /proc/$PID/ns/net)"
fi
