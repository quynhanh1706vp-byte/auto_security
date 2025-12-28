#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v node >/dev/null 2>&1 && HAVE_NODE=1 || HAVE_NODE=0
command -v systemctl >/dev/null 2>&1 && HAVE_SYSTEMCTL=1 || HAVE_SYSTEMCTL=0

WSGI="wsgi_vsp_ui_gateway.py"
JS="static/js/vsp_dashboard_luxe_v1.js"

ok "CWD=$(pwd)"
ok "SVC=$SVC BASE=$BASE"

restore_latest(){
  local target="$1" pattern="$2"
  local bak
  bak="$(ls -1t $pattern 2>/dev/null | head -n 1 || true)"
  if [ -n "${bak:-}" ] && [ -f "$bak" ]; then
    cp -f "$bak" "$target"
    ok "RESTORE $target <= $bak"
    return 0
  fi
  warn "no backup matched: $pattern"
  return 1
}

say_section(){ echo; echo "== $* =="; }

say_section "1) Compile check WSGI"
if python3 -m py_compile "$WSGI" 2>/tmp/vsp_pycompile_err.txt; then
  ok "WSGI py_compile OK"
else
  warn "WSGI py_compile FAILED => rollback to latest bak_kpiappctx"
  tail -n 30 /tmp/vsp_pycompile_err.txt >&2 || true
  restore_latest "$WSGI" "${WSGI}.bak_kpiappctx_*" || restore_latest "$WSGI" "${WSGI}.bak_*"
  python3 -m py_compile "$WSGI"
  ok "WSGI rollback compile OK"
fi

say_section "2) JS sanity check"
if [ "$HAVE_NODE" = "1" ]; then
  if node --check "$JS" >/tmp/vsp_nodecheck_out.txt 2>&1; then
    ok "JS node --check OK"
  else
    warn "JS node --check FAILED => rollback to latest bak_kpirid"
    tail -n 20 /tmp/vsp_nodecheck_out.txt >&2 || true
    restore_latest "$JS" "${JS}.bak_kpirid_*" || restore_latest "$JS" "${JS}.bak_*"
    node --check "$JS" >/dev/null
    ok "JS rollback check OK"
  fi
else
  warn "node not found; skip JS syntax check"
fi

say_section "3) Restart service"
if [ "$HAVE_SYSTEMCTL" = "1" ]; then
  systemctl restart "$SVC" || true
  systemctl status "$SVC" --no-pager -l | head -n 40 || true
else
  warn "systemctl not found; cannot restart automatically"
fi

say_section "4) Wait for /ready"
for i in $(seq 1 60); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/ready" >/dev/null 2>&1; then
    ok "/ready is up"
    break
  fi
  sleep 0.25
done

say_section "5) Quick verify APIs"
RID="$(curl -fsS --connect-timeout 1 --max-time 3 "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))' 2>/dev/null || true)"
echo "RID=$RID"
if [ -n "${RID:-}" ]; then
  curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID" | head -c 400; echo
  curl -fsS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 400; echo
else
  warn "rid_latest empty or API not reachable; show status/log tail"
  curl -sS -o /dev/null -w "GET /ready => %{http_code}\n" "$BASE/ready" || true
  if [ "$HAVE_SYSTEMCTL" = "1" ]; then
    journalctl -u "$SVC" --no-pager -n 120 | tail -n 60 || true
  fi
fi
