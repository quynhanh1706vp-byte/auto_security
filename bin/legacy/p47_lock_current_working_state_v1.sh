#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_lock_state_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need date; need python3; need ls; need head; need sudo; need systemctl; need curl; need sha256sum

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG" >&2; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }

GW="wsgi_vsp_ui_gateway.py"
APP="vsp_demo_app.py"

probe(){ curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$1" 2>/dev/null || true; }

ok "== [P47 LOCK] ts=$TS base=$BASE svc=$SVC =="

compile_ok=1
if ! python3 -m py_compile "$GW" >>"$LOG" 2>&1; then
  warn "py_compile FAIL: $GW"
  compile_ok=0
fi
if ! python3 -m py_compile "$APP" >>"$LOG" 2>&1; then
  warn "py_compile FAIL: $APP"
  compile_ok=0
fi

restore_from_backup(){
  local f="$1"
  local picked=""
  for b in $(ls -1t ${f}.bak_* 2>/dev/null | head -n 200); do
    if python3 -m py_compile "$b" >/dev/null 2>&1; then picked="$b"; break; fi
  done
  [ -n "$picked" ] || fail "no compile-pass backup for $f"
  cp -f "$f" "${f}.bak_before_lock_${TS}"
  cp -f "$picked" "$f"
  ok "RESTORED $f from $picked"
  python3 -m py_compile "$f" >>"$LOG" 2>&1 || fail "still compile fail after restore: $f"
}

if [ "$compile_ok" -eq 0 ]; then
  warn "compile not safe -> restoring from backups + restart to ensure future restart won't brick"
  restore_from_backup "$GW"
  restore_from_backup "$APP"
  ok "restart $SVC"
  sudo systemctl restart "$SVC" || true
fi

# Verify health (allow a little time)
pass=0
for i in $(seq 1 25); do
  c1="$(probe "$BASE/vsp5")"
  c2="$(probe "$BASE/api/vsp/runs?limit=1&offset=0")"
  c3="$(probe "$BASE/api/vsp/dashboard_extras_v1")"
  if [ "$c1" = "200" ] && [ "$c2" = "200" ] && [ "$c3" = "200" ]; then pass=1; break; fi
  sleep 0.4
done
[ "$pass" -eq 1 ] || fail "health check failed (vsp5/runs/extras not 200)"

ok "HEALTH OK: /vsp5 + /api/vsp/runs + /api/vsp/dashboard_extras_v1"

# Write golden snapshot
snap="$OUT/p47_golden_snapshot_${TS}.json"
python3 - <<PY >"$snap"
import json, hashlib, pathlib, datetime, os
def sha(p):
    b=pathlib.Path(p).read_bytes()
    return hashlib.sha256(b).hexdigest()
j={
  "ts": datetime.datetime.utcnow().isoformat()+"Z",
  "svc": "${SVC}",
  "base": "${BASE}",
  "files": {
    "${GW}": {"sha256": sha("${GW}")},
    "${APP}": {"sha256": sha("${APP}")},
  }
}
print(json.dumps(j, indent=2))
PY
ok "wrote snapshot: $snap"
ok "log: $LOG"
