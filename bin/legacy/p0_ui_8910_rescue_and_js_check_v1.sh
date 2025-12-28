#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ss; need sed; need awk; need grep; need tail; need curl; need date

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
ELOG="out_ci/ui_8910.error.log"
BLOG="out_ci/ui_8910.boot.log"
PIDF="out_ci/ui_8910.pid"

echo "== (A) JS syntax check (if node exists) =="
if command -v node >/dev/null 2>&1; then
  chk(){
    local f="$1"
    [ -f "$f" ] || return 0
    echo "--- node --check $f ---"
    local out rc
    out="$(node --check "$f" 2>&1)" || rc=$?
    if [ -z "${rc:-}" ]; then
      echo "[OK] $f"
      return 0
    fi
    echo "[ERR] $f"
    echo "$out"
    # extract "file:LINE" from node output
    local line
    line="$(printf "%s\n" "$out" | sed -n 's/.*:\([0-9]\+\)\s*$/\1/p' | head -n1)"
    if [[ "${line:-}" =~ ^[0-9]+$ ]]; then
      echo "== context around line $line =="
      local s=$((line-10)); [ $s -lt 1 ] && s=1
      local e=$((line+10))
      nl -ba "$f" | sed -n "${s},${e}p" || true
    fi
    exit 9
  }
  chk static/js/vsp_bundle_commercial_v2.js
  chk static/js/vsp_bundle_commercial_v1.js
  chk static/js/vsp_dashboard_gate_story_v1.js
else
  echo "[WARN] node not found -> skip JS syntax check"
fi

echo
echo "== (B) listener :8910 before =="
ss -ltnp 2>/dev/null | egrep '(:8910)\b' || echo "[INFO] no listener on :8910"

echo
echo "== (C) try restart via systemd (if exists) =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart vsp-ui-8910.service 2>/dev/null || true
  sudo systemctl --no-pager --full status vsp-ui-8910.service 2>/dev/null | sed -n '1,80p' || true
fi

sleep 0.7

echo
echo "== (D) if still no listener, fallback start script =="
if ! ss -ltnp 2>/dev/null | egrep -q '(:8910)\b'; then
  echo "[WARN] still no :8910 listener -> attempt fallback start"
  rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
  [ -f "$PIDF" ] && rm -f "$PIDF" || true

  # kill any stale gunicorn bound to 8910
  PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
  if [ -n "${PIDS// }" ]; then
    echo "[INFO] killing stale listener pids: $PIDS"
    kill -9 $PIDS 2>/dev/null || true
  fi

  if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
    bin/p1_ui_8910_single_owner_start_v2.sh || true
  else
    echo "[ERR] missing bin/p1_ui_8910_single_owner_start_v2.sh"
  fi
fi

sleep 0.7

echo
echo "== (E) listener :8910 after =="
ss -ltnp 2>/dev/null | egrep '(:8910)\b' || echo "[ERR] still no listener on :8910"

echo
echo "== (F) quick verify =="
curl -sS -I "$BASE/" | sed -n '1,12p' || true
curl -sS -I "$BASE/vsp5" | sed -n '1,12p' || true
curl -sS "$BASE/api/vsp/runs?limit=1" | head -c 300; echo

echo
echo "== (G) tail logs =="
[ -f "$BLOG" ] && { echo "--- $BLOG (last 80) ---"; tail -n 80 "$BLOG"; } || true
[ -f "$ELOG" ] && { echo "--- $ELOG (last 120) ---"; tail -n 120 "$ELOG"; } || true

echo
echo "[OK] done"
