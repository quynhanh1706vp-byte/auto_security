#!/usr/bin/env bash
# VSP UI OPS (SAFE): never kill your CLI if someone accidentally "source"s it.
# Usage:
#   bash bin/vsp_ui_ops_safe_v2.sh status|smoke|pack|rollback|restart
set -u

# If sourced, do NOT poison the parent shell.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "[ERR] Do NOT source this script. Run: bash ${BASH_SOURCE[0]} <cmd>"
  return 2
fi

set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

W="wsgi_vsp_ui_gateway.py"
A="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need curl; need ls; need head; need date

sudo_n(){
  command -v sudo >/dev/null 2>&1 || return 1
  sudo -n true >/dev/null 2>&1 || return 1
  sudo -n "$@"
}

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
fail(){ echo "[FAIL] $*" >&2; exit 1; }

wait_port(){
  for i in $(seq 1 120); do
    curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1 && { ok "UI up: $BASE"; return 0; }
    sleep 0.25
  done
  return 1
}

smoke_tabs(){
  local paths=(/vsp5 /runs /data_source /settings /rule_overrides /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
  echo "== [tabs] =="
  for p in "${paths[@]}"; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 6 "$BASE$p?rid=$RID" || true)"
    echo "$p => $code"
  done
}

smoke_api(){
  echo "== [api] =="
  local arr=(
    "/api/vsp/runs?limit=1&offset=0"
    "/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0"
    "/api/vsp/top_findings_v3c?rid=$RID&limit=50"
    "/api/vsp/trend_v1"
    "/api/vsp/rule_overrides_v1"
  )
  for a in "${arr[@]}"; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 8 "$BASE$a" || true)"
    echo "API $a => $code"
  done
}

pick_compile_backup(){
  # pick newest backup that compiles
  local f="$1"
  local b
  for b in $(ls -1t "${f}.bak_"* 2>/dev/null || true); do
    if python3 -m py_compile "$b" >/dev/null 2>&1; then
      echo "$b"
      return 0
    fi
  done
  return 1
}

cmd="${1:-}"
case "$cmd" in
  status)
    echo "BASE=$BASE RID=$RID SVC=$SVC"
    command -v systemctl >/dev/null 2>&1 && systemctl is-active "$SVC" || true
    wait_port || fail "UI not reachable: $BASE"
    ;;
  restart)
    if sudo_n systemctl daemon-reload && sudo_n systemctl restart "$SVC"; then
      ok "restarted: $SVC"
      wait_port || fail "UI not reachable after restart"
    else
      warn "cannot sudo -n restart. Run manually:"
      echo "  sudo systemctl daemon-reload"
      echo "  sudo systemctl restart $SVC"
      exit 1
    fi
    ;;
  smoke)
    command -v systemctl >/dev/null 2>&1 && systemctl is-active "$SVC" || true
    wait_port || fail "UI not reachable: $BASE"
    smoke_tabs
    smoke_api
    ok "SMOKE done"
    ;;
  pack)
    # call your proven packer if exists
    if [ -f bin/p0_market_release_pack_v1.sh ]; then
      RID="$RID" bash bin/p0_market_release_pack_v1.sh
      ok "PACK done"
    else
      fail "missing: bin/p0_market_release_pack_v1.sh"
    fi
    ;;
  rollback)
    echo "== [rollback] pick last compiling backups =="
    BW="$(pick_compile_backup "$W" || true)"
    BA="$(pick_compile_backup "$A" || true)"
    [ -n "${BW:-}" ] || fail "no compiling backup for $W"
    [ -n "${BA:-}" ] || fail "no compiling backup for $A"
    echo "[RESTORE]"
    echo " - $W <= $BW"
    echo " - $A <= $BA"
    cp -f "$BW" "$W"
    cp -f "$BA" "$A"
    if sudo_n systemctl daemon-reload && sudo_n systemctl restart "$SVC"; then
      ok "rolled back + restarted: $SVC"
      wait_port || fail "UI not reachable after rollback"
    else
      warn "rollback applied but cannot sudo -n restart. Run manually:"
      echo "  sudo systemctl daemon-reload"
      echo "  sudo systemctl restart $SVC"
      exit 1
    fi
    ;;
  *)
    echo "Usage: bash $0 status|restart|smoke|pack|rollback"
    exit 2
    ;;
esac
