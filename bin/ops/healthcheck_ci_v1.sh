#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
UNIT="${GH_RUNNER_UNIT:-gh-runner.service}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

OUT="out_ci/ops_healthcheck"
TS="$(date +%Y%m%d_%H%M%S)"
DIR="$OUT/$TS"
mkdir -p "$DIR"

log(){ echo "$*" | tee -a "$DIR/healthcheck.log"; }

log "== OPS HEALTHCHECK TS=$TS =="
log "BASE=$BASE SVC=$SVC UNIT=$UNIT"

log "== UI endpoints =="
ok=0
for p in "/api/vsp/healthz" "/api/vsp/healthz_v1" "/healthz" "/vsp5" "/c/dashboard"; do
  code="$(curl --noproxy '*' -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 6 "$BASE$p" || true)"
  log "GET $p => $code"
  [ "$code" = "200" ] && ok=1
done
[ "$ok" = "1" ] && log "[OK] UI reachable" || log "[FAIL] UI not healthy"

log "== runner unit (best-effort) =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user is-active "$UNIT" >/dev/null 2>&1 && log "[OK] runner active" || log "[WARN] runner not active"
fi

ps aux | egrep -i "Runner.Listener|actions-runner|runsvc|run.sh" | grep -v egrep > "$DIR/runner_ps.txt" || true
[ -s "$DIR/runner_ps.txt" ] && log "[OK] runner process markers found" || log "[WARN] no runner process markers"

log "[OK] evidence => $DIR"
