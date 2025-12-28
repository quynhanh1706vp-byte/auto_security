#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
LOGDIR="/var/log/vsp-ui-8910"
RULE="/etc/logrotate.d/vsp-ui-8910"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p48_0b_${TS}"
mkdir -p "$OUT" "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need grep; need awk; need sed; need head; need tail; need ls; need cp; need mkdir; need python3
need logrotate
need sudo
command -v systemctl >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*"; }

log "== [P48.0b/0] locate latest release =="
latest_release=""
if [ -d "$RELROOT" ]; then
  latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
fi
if [ -n "${latest_release:-}" ] && [ -d "$latest_release" ]; then
  log "[OK] latest_release=$latest_release"
else
  log "[WARN] no release found; evidence stays in $EVID"
fi

log "== [P48.0b/1] run logrotate -d with /tmp state (avoid out_ci noise) =="
DRY="$EVID/logrotate_dryrun_${TS}.txt"
STATE="/tmp/vsp_p48_0b_logrotate_${TS}.state"
( sudo logrotate -d -s "$STATE" "$RULE" ) >"$DRY" 2>&1 || {
  tail -n 120 "$DRY" >&2
  echo "[FAIL] logrotate -d failed" >&2
  exit 2
}
log "[OK] logrotate -d OK (state=$STATE)"

log "== [P48.0b/2] strict check: must NOT consider/rotate any out_ci logs =="
# Only fail if logrotate is actually handling out_ci paths (not mere mentions).
BAD="$EVID/bad_outci_lines_${TS}.txt"
grep -nE '(considering log|rotating pattern|log ->|renaming|compressing|copying|creating) .*out_ci/' "$DRY" > "$BAD" || true

if [ -s "$BAD" ]; then
  log "[FAIL] detected real out_ci rotation activity (see $BAD)"
  OK=0
  REASON="out_ci_rotation_detected"
else
  log "[OK] no out_ci log rotation activity"
  OK=1
  REASON=""
fi

log "== [P48.0b/3] attach evidence into latest release (if exists) =="
if [ -n "${latest_release:-}" ] && [ -d "$latest_release" ]; then
  mkdir -p "$latest_release/evidence/p48_0b_${TS}"
  cp -f "$EVID/"* "$latest_release/evidence/p48_0b_${TS}/" 2>/dev/null || true

  # attach previous failing p48 verdict too (audit chain)
  p48_fail="$(ls -1t "$OUT"/p48_verdict_*.json 2>/dev/null | head -n 1 || true)"
  if [ -n "$p48_fail" ] && [ -f "$p48_fail" ]; then
    cp -f "$p48_fail" "$latest_release/evidence/p48_0b_${TS}/" || true
    log "[OK] attached $(basename "$p48_fail")"
  fi
fi

log "== [P48.0b/4] verdict json =="
VERDICT="$OUT/p48_0b_verdict_${TS}.json"
python3 - <<PY
import json, time
ok = bool(int("$OK"))
reasons = []
if "$REASON":
    reasons.append("$REASON")
verdict = {
  "ok": ok,
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "p48_0b": {
    "service": "$SVC",
    "rule": "$RULE",
    "logdir": "$LOGDIR",
    "latest_release": "${latest_release:-""}",
    "evidence_dir": "$EVID",
    "reasons": reasons
  }
}
print(json.dumps(verdict, indent=2))
open("$VERDICT","w").write(json.dumps(verdict, indent=2))
PY

if [ "$OK" -eq 1 ]; then
  log "[PASS] wrote $VERDICT"
  log "[DONE] P48.0b PASS (P48 fail was false-positive)"
else
  log "[FAIL] wrote $VERDICT"
  log "[DONE] P48.0b FAIL"
  exit 2
fi
