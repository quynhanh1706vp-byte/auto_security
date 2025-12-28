#!/usr/bin/env bash
# VSP UI OPS (SAFE v3): deterministic smoke (retry + per-endpoint timeout + latency)
# Usage:
#   bash bin/vsp_ui_ops_safe_v3.sh status|smoke|pack|rollback|restart
set -u
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "[ERR] Do NOT source this script. Run: bash ${BASH_SOURCE[0]} <cmd>"
  return 2
fi
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need awk; need sed; need grep; need date

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
fail(){ echo "[FAIL] $*" >&2; return 1; }

status(){
  echo "BASE=$BASE RID=$RID SVC=$SVC"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active "$SVC" || true
  fi
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1 && ok "UI up: $BASE" || warn "UI not reachable: $BASE"
}

_restart_try(){
  if command -v systemctl >/dev/null 2>&1; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      sudo -n systemctl daemon-reload || true
      sudo -n systemctl restart "$SVC"
      ok "restarted: $SVC"
      return 0
    fi
    warn "sudo -n not allowed. Run manually:"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl restart $SVC"
    return 2
  fi
  warn "systemctl not available"
  return 2
}

_wait_port(){
  local i
  for i in $(seq 1 120); do
    curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1 && { ok "UI up: $BASE"; return 0; }
    sleep 0.25
  done
  return 1
}

_probe(){
  # _probe <url> <max_time> <retries>
  local url="$1" mt="$2" retries="$3"
  local attempt=1 code t
  while [ "$attempt" -le "$retries" ]; do
    # print: CODE TIME
    read -r code t < <(curl -sS -o /dev/null -w "%{http_code} %{time_total}" \
      --connect-timeout 2 --max-time "$mt" "$url" 2>/dev/null || echo "000 0")
    echo "code=$code time=${t}s url=$url (try $attempt/$retries)"
    if [ "$code" = "200" ]; then return 0; fi
    attempt=$((attempt+1))
    sleep 0.4
  done
  return 1
}

smoke(){
  local rc=0
  echo "BASE=$BASE RID=$RID SVC=$SVC"
  command -v systemctl >/dev/null 2>&1 && systemctl is-active "$SVC" || true

  echo "== [1] wait port =="
  _wait_port || { fail "UI not reachable: $BASE"; return 1; }

  echo "== [tabs] =="
  local p code
  for p in /vsp5 /runs /data_source /settings /rule_overrides /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 6 "$BASE$p?rid=$RID" || true)"
    echo "$p => $code"
    # allow 200 and 302 for /c/*
    if [[ "$p" == /c/* ]]; then
      [[ "$code" == "200" || "$code" == "302" ]] || rc=1
    else
      [[ "$code" == "200" ]] || rc=1
    fi
  done

  echo "== [api] =="
  # nhẹ: 8s, riêng findings_page: 20s + retry 3
  _probe "$BASE/api/vsp/runs?limit=1&offset=0" 8 2 || rc=1
  _probe "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0" 20 3 || rc=1
  _probe "$BASE/api/vsp/top_findings_v3c?rid=$RID&limit=50" 10 2 || rc=1
  _probe "$BASE/api/vsp/trend_v1" 8 2 || rc=1
  _probe "$BASE/api/vsp/rule_overrides_v1" 8 2 || rc=1

  if [ "$rc" -eq 0 ]; then
    ok "SMOKE: GREEN ✅"
    return 0
  else
    fail "SMOKE: AMBER/RED ❌ (see non-200 above)"
    return 1
  fi
}

pack(){
  ok "packing market release (RID=$RID)"
  RID="$RID" bash bin/p0_market_release_pack_v1.sh
}

rollback(){
  ok "rollback to last-good backups"
  bash bin/p0_rollback_last_good_v1.sh
  _restart_try || true
}

restart(){
  _restart_try || return $?
  _wait_port || return 1
}

cmd="${1:-}"
case "$cmd" in
  status) status ;;
  smoke)  smoke ;;
  pack)   pack ;;
  rollback) rollback ;;
  restart) restart ;;
  *)
    echo "Usage: bash $0 status|smoke|pack|rollback|restart"
    exit 2
    ;;
esac
