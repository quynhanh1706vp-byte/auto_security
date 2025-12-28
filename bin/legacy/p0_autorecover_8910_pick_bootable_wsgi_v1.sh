#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need ss; need awk; need sed; need grep
command -v fuser >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
GUNI="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn"
PYV="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
BASE="http://127.0.0.1:8910"
ENDPOINT="/vsp5"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }
[ -x "$GUNI" ] || { echo "[ERR] missing gunicorn $GUNI"; exit 2; }
[ -x "$PYV" ]  || { echo "[ERR] missing python venv $PYV"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
SNAP="${WSGI}.bak_before_bootpick_${TS}"
cp -f "$WSGI" "$SNAP"
echo "[BACKUP] $SNAP"

echo "== stop service =="
systemctl stop "$SVC" 2>/dev/null || true
systemctl reset-failed "$SVC" 2>/dev/null || true

echo "== free port 8910 =="
if command -v fuser >/dev/null 2>&1; then fuser -k 8910/tcp 2>/dev/null || true; fi
PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910/{print}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS 2>/dev/null || true

echo "== build candidate list (newest first) =="
mapfile -t BAKS < <(ls -1t wsgi_vsp_ui_gateway.py.bak_* 2>/dev/null || true)
if [ "${#BAKS[@]}" -eq 0 ]; then
  echo "[ERR] no backup files found: wsgi_vsp_ui_gateway.py.bak_*"
  exit 2
fi
echo "[INFO] backups=${#BAKS[@]} (will try up to 80 newest compile-ok candidates)"

BOOT_OK=""
BOOT_LOG="/tmp/vsp_8910_bootpick_${TS}.log"

try_one(){
  local bak="$1"
  echo "---- TRY: $bak ----" | tee -a "$BOOT_LOG"

  # compile test (venv python to match runtime)
  if ! "$PYV" - <<PY >>"$BOOT_LOG" 2>&1
import py_compile, sys
py_compile.compile("$bak", doraise=True)
print("PY_COMPILE_OK")
PY
  then
    echo "[SKIP] compile failed: $bak" | tee -a "$BOOT_LOG"
    return 1
  fi

  # apply candidate
  cp -f "$bak" "$WSGI"

  # start gunicorn minimal (1 worker) and hit /vsp5 once
  local gp="/tmp/vsp_8910_bootpick_guni_${TS}_$$.pid"
  rm -f "$gp" 2>/dev/null || true

  set +e
  "$GUNI" wsgi_vsp_ui_gateway:application \
    --workers 1 --log-level info --worker-class gthread --threads 2 \
    --timeout 30 --graceful-timeout 10 \
    --chdir /home/test/Data/SECURITY_BUNDLE/ui \
    --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
    --bind 127.0.0.1:8910 \
    --error-logfile - --access-logfile - \
    >>"$BOOT_LOG" 2>&1 &
  local pid=$!
  echo "$pid" > "$gp"
  set -e

  # wait boot
  for i in $(seq 1 25); do
    ss -ltn 2>/dev/null | grep -q ":8910" && break
    sleep 0.1
  done

  # curl check (need HTTP 200-ish)
  local ok=0
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE$ENDPOINT" >/dev/null 2>&1; then
    ok=1
  fi

  # kill gunicorn
  kill "$pid" 2>/dev/null || true
  sleep 0.2
  kill -9 "$pid" 2>/dev/null || true

  if [ "$ok" -eq 1 ]; then
    echo "[BOOT_OK] $bak" | tee -a "$BOOT_LOG"
    BOOT_OK="$bak"
    return 0
  fi

  echo "[BOOT_FAIL] $bak" | tee -a "$BOOT_LOG"
  return 1
}

MAX=80
cnt=0
for b in "${BAKS[@]}"; do
  cnt=$((cnt+1))
  [ "$cnt" -gt "$MAX" ] && break
  if try_one "$b"; then
    break
  fi
done

if [ -z "$BOOT_OK" ]; then
  echo
  echo "[ERR] No bootable backup found (checked up to $MAX)."
  echo "[HINT] View boot log: $BOOT_LOG"
  echo "  tail -n 120 $BOOT_LOG"
  exit 2
fi

echo
echo "== APPLY bootable candidate to WSGI and restart systemd =="
cp -f "$BOOT_OK" "$WSGI"
"$PYV" -m py_compile "$WSGI" && echo "[OK] py_compile final OK"

systemctl restart "$SVC" || true
systemctl --no-pager --full status "$SVC" | sed -n '1,25p' || true

echo
echo "== VERIFY =="
curl -fsS -I "$BASE$ENDPOINT" | head -n 10 || true
curl -fsS "$BASE/api/vsp/runs?limit=1" | head -c 220; echo || true

echo
echo "[DONE] picked bootable WSGI: $BOOT_OK"
echo "[LOG] $BOOT_LOG"
