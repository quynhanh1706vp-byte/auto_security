#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SERVICE="vsp-ui-8910.service"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
LOGDIR="out_ci"
BOOTLOG="$LOGDIR/ui_8910.boot_rescue.log"
FALLLOG="$LOGDIR/ui_8910.fallback_gunicorn.log"

mkdir -p "$LOGDIR"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ss; need sed; need awk; need grep; need curl; need date

echo "== [0] snapshot =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rescue_${TS}"
echo "[SNAPSHOT] ${W}.bak_rescue_${TS}"

echo "== [1] stop systemd service (ignore errors) =="
systemctl stop "$SERVICE" 2>/dev/null || true

echo "== [2] kill anything listening on :8910 =="
PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// }" ]; then
  echo "[KILL] $PIDS"
  kill -9 $PIDS 2>/dev/null || true
else
  echo "[OK] no listeners on 8910"
fi

echo "== [3] remove lock(s) =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true

echo "== [4] py_compile + import smoke (capture errors) =="
: > "$BOOTLOG"
python3 -m py_compile "$W" >>"$BOOTLOG" 2>&1 || true
python3 - <<'PY' >>"$BOOTLOG" 2>&1 || true
import importlib, traceback, sys
try:
    m = importlib.import_module("wsgi_vsp_ui_gateway")
    print("[IMPORT] OK")
    for k in ("app","application"):
        v = getattr(m,k,None)
        print(f"[IMPORT] {k}=", type(v), v is not None)
except Exception as e:
    print("[IMPORT] FAIL:", e)
    traceback.print_exc()
    sys.exit(3)
PY
echo "[LOG] $BOOTLOG (tail 60)"
tail -n 60 "$BOOTLOG" || true

echo "== [5] restart systemd service =="
systemctl restart "$SERVICE" 2>/dev/null || true
sleep 0.8

echo "== [6] check systemd + port =="
systemctl --no-pager -l status "$SERVICE" | sed -n '1,80p' || true
ss -ltnp 2>/dev/null | grep -E ':8910\b' || true

echo "== [7] curl sanity (v2 endpoint) =="
if curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 180; then
  echo
  echo "[OK] 8910 is up via systemd"
  exit 0
fi
echo
echo "[WARN] systemd path not serving. Collect journal tail..."
journalctl -u "$SERVICE" -n 200 --no-pager >>"$BOOTLOG" 2>/dev/null || true
echo "[LOG+] appended journal tail => $BOOTLOG"

echo "== [8] fallback: start gunicorn directly (background) =="
need gunicorn
# kill again just in case
PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS 2>/dev/null || true

: > "$FALLLOG"
nohup gunicorn -w 1 -b 127.0.0.1:8910 --timeout 120 --access-logfile - --error-logfile - wsgi_vsp_ui_gateway:app >>"$FALLLOG" 2>&1 &
sleep 1.0
ss -ltnp 2>/dev/null | grep -E ':8910\b' || true

echo "== [9] curl sanity again =="
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 220; echo
echo "[OK] fallback gunicorn up. logs: $FALLLOG"
exit 0
