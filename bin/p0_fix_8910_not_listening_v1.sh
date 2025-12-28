#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ss; need sed; need awk; need grep; need tail; need curl; need bash

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PIDF="out_ci/ui_8910.pid"
ELOG="out_ci/ui_8910.error.log"
ALOG="out_ci/ui_8910.access.log"
BLOG="out_ci/ui_8910.boot.log"

echo "== ss :8910 (before) =="
ss -ltnp 2>/dev/null | egrep '(:8910)\b' || echo "[INFO] no listener on :8910"

echo "== quick curl (before) =="
curl -sS -I "$BASE/" | sed -n '1,8p' || true

fix_kill(){
  echo "== cleanup lock/pid =="
  rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true

  if [ -f "$PIDF" ]; then
    P="$(cat "$PIDF" 2>/dev/null || true)"
    if [[ "${P:-}" =~ ^[0-9]+$ ]]; then
      echo "[INFO] kill pid from $PIDF: $P"
      kill -9 "$P" 2>/dev/null || true
    fi
  fi

  echo "== kill any gunicorn binding 127.0.0.1:8910 =="
  PIDS="$(ps aux | grep -E 'gunicorn .*--bind 127\.0\.0\.1:8910' | grep -v grep | awk '{print $2}' | tr '\n' ' ')"
  if [ -n "${PIDS// }" ]; then
    echo "[INFO] kill PIDS: $PIDS"
    kill -9 $PIDS 2>/dev/null || true
  fi
}

show_logs(){
  echo "== tail boot/error logs (if any) =="
  [ -f "$BLOG" ] && { echo "--- $BLOG (last 120) ---"; tail -n 120 "$BLOG"; } || true
  [ -f "$ELOG" ] && { echo "--- $ELOG (last 200) ---"; tail -n 200 "$ELOG"; } || true
}

ensure_start(){
  echo "== start UI 8910 =="
  if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
    bin/p1_ui_8910_single_owner_start_v2.sh || true
  else
    echo "[ERR] missing bin/p1_ui_8910_single_owner_start_v2.sh"
    exit 2
  fi
}

# if not listening -> recover
if ! ss -ltnp 2>/dev/null | egrep -q '(:8910)\b'; then
  echo "[WARN] :8910 not listening -> dump logs + clean restart"
  show_logs
  fix_kill
  ensure_start
  sleep 1.0
fi

echo "== ss :8910 (after) =="
ss -ltnp 2>/dev/null | egrep '(:8910)\b' || { echo "[ERR] still not listening on :8910"; show_logs; exit 3; }

echo "== verify endpoints (after) =="
curl -sS -I "$BASE/" | sed -n '1,12p'
echo "--- /api/vsp/open ---"
curl -sS "$BASE/api/vsp/open" | head -c 220; echo
echo "--- /api/vsp/runs?limit=2 ---"
curl -sS "$BASE/api/vsp/runs?limit=2" | head -c 900; echo

echo "[OK] done"
