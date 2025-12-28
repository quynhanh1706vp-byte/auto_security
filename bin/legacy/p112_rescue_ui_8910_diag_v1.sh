#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PORT="${VSP_UI_PORT:-8910}"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }
err(){ echo "[ERR] $*"; }

need(){ command -v "$1" >/dev/null 2>&1 || { err "missing: $1"; exit 2; }; }
need systemctl; need journalctl; need bash; need date
command -v ss >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v python3 >/dev/null 2>&1 || true

echo "== [P112] status before =="
systemctl is-active "$SVC" || true
systemctl --no-pager -l status "$SVC" | head -n 40 || true

echo
echo "== [P112] restart =="
sudo systemctl restart "$SVC" || true
sleep 1

echo
echo "== [P112] wait port+http (max 30s) =="
up=0
for i in $(seq 1 30); do
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" -o /dev/null 2>/dev/null; then
      up=1; break
    fi
  fi
  sleep 1
done

if [ "$up" -eq 1 ]; then
  ok "UI is UP: $BASE"
  if command -v ss >/dev/null 2>&1; then
    echo "== [P112] listen check =="
    ss -ltnp 2>/dev/null | grep -E ":(8910|$PORT)\b" || true
  fi
  echo "== [P112] quick health =="
  for p in /vsp5 /runs /data_source /settings /rule_overrides; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 4 "$BASE$p" || echo "000")"
    echo "$p => $code"
  done
  exit 0
fi

warn "UI still DOWN after restart. Printing diagnostics…"

echo
echo "== [P112] status after =="
systemctl is-active "$SVC" || true
systemctl --no-pager -l status "$SVC" | head -n 120 || true

echo
echo "== [P112] journal tail =="
journalctl -u "$SVC" --no-pager -n 160 || true

echo
echo "== [P112] common quick checks =="
if command -v python3 >/dev/null 2>&1; then
  echo "-- py_compile wsgi_vsp_ui_gateway.py --"
  python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile ok" || echo "[ERR] py_compile failed"
  echo "-- py_compile vsp_demo_app.py (if exists) --"
  if [ -f vsp_demo_app.py ]; then
    python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile ok" || echo "[ERR] py_compile failed"
  fi
fi

echo
err "P112 done: service is not responding. Paste the last ~60 lines of 'journal tail' above."
exit 1
