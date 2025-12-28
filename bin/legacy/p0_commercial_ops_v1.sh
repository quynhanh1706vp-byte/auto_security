#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

W="wsgi_vsp_ui_gateway.py"
A="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need head; need curl

sudo_n(){
  command -v sudo >/dev/null 2>&1 || return 1
  sudo -n true >/dev/null 2>&1 || return 1
  sudo -n "$@"
}

restart_no_prompt(){
  if command -v systemctl >/dev/null 2>&1; then
    if sudo_n systemctl daemon-reload && sudo_n systemctl restart "$SVC"; then
      echo "[OK] restarted: $SVC"
    else
      echo "[WARN] cannot sudo -n restart. Run manually:"
      echo "  sudo systemctl daemon-reload"
      echo "  sudo systemctl restart $SVC"
    fi
  else
    echo "[WARN] systemctl not found (skip restart)"
  fi
}

pick_last_compiling(){
  local file="$1"
  local pat="${file}.bak_*"
  local tmp="/tmp/vsp_pick_compile_$$"
  rm -rf "$tmp"; mkdir -p "$tmp"

  local b
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    cp -f "$b" "$tmp/$file" || continue
    if python3 -m py_compile "$tmp/$file" >/dev/null 2>&1; then
      echo "$b"
      rm -rf "$tmp"
      return 0
    fi
  done < <(ls -1t $pat 2>/dev/null || true)

  rm -rf "$tmp"
  return 1
}

rollback_compile_safe(){
  echo "== [rollback] pick last compiling backups =="
  local BW BA
  BW="$(pick_last_compiling "$W" || true)"
  BA="$(pick_last_compiling "$A" || true)"

  [ -n "${BW:-}" ] || { echo "[ERR] no compiling backup for $W"; exit 2; }
  [ -n "${BA:-}" ] || { echo "[ERR] no compiling backup for $A"; exit 2; }

  echo "[RESTORE]"
  echo " - $W <= $BW"
  echo " - $A <= $BA"
  cp -f "$BW" "$W"
  cp -f "$BA" "$A"

  python3 -m py_compile "$W" "$A"
  restart_no_prompt
}

smoke(){
  echo "== [smoke] =="
  RID="$RID" BASE="$BASE" SVC="$SVC" bash bin/p0_go_live_smoke_v1.sh
}

pack(){
  echo "== [pack] =="
  RID="$RID" BASE="$BASE" SVC="$SVC" bash bin/p0_market_release_pack_v1.sh
}

status(){
  echo "BASE=$BASE RID=$RID SVC=$SVC"
  command -v systemctl >/dev/null 2>&1 && systemctl is-active "$SVC" || true
  curl -fsS --connect-timeout 1 --max-time 3 "$BASE/vsp5" >/dev/null 2>&1 && echo "[OK] UI up" || echo "[WARN] UI down"
}

usage(){
  cat <<USAGE
Usage:
  bash bin/p0_commercial_ops_v1.sh status
  bash bin/p0_commercial_ops_v1.sh restart
  bash bin/p0_commercial_ops_v1.sh smoke
  bash bin/p0_commercial_ops_v1.sh pack
  bash bin/p0_commercial_ops_v1.sh rollback
Notes:
  - DO NOT run via: source bin/p0_commercial_ops_v1.sh
USAGE
}

cmd="${1:-}"
case "$cmd" in
  status) status ;;
  restart) restart_no_prompt ;;
  smoke) smoke ;;
  pack) pack ;;
  rollback) rollback_compile_safe ;;
  *) usage; exit 2 ;;
esac
