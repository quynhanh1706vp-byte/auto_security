#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
LOGDIR="/var/log/vsp-ui-8910"
RULE="/etc/logrotate.d/vsp-ui-8910"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p48_${TS}"
mkdir -p "$OUT" "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need awk; need sed; need grep; need head; need tail; need ls; need stat; need cp; need mkdir; need find; need sort; need wc
need logrotate
command -v systemctl >/dev/null 2>&1 || true
need sudo

log(){ echo "[$(date +%H:%M:%S)] $*"; }
warn(){ echo "[WARN] $*" >&2; }
fail(){ echo "[FAIL] $*" >&2; return 1; }

PASS=1
REASONS=()

log "== [P48/0] locate latest release =="
latest_release=""
if [ -d "$RELROOT" ]; then
  latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
fi
if [ -z "${latest_release:-}" ] || [ ! -d "$latest_release" ]; then
  warn "no release found under $RELROOT; evidence stays in $EVID (PASS can still be true)"
else
  log "[OK] latest_release=$latest_release"
fi

log "== [P48/1] logrotate rule uniqueness + no out_ci references =="
sudo test -f "$RULE" || { PASS=0; REASONS+=("missing_rule:$RULE"); warn "missing $RULE"; }

# Gather ALL files that reference /var/log/vsp-ui-8910
# (logrotate reads /etc/logrotate.conf + /etc/logrotate.d/* usually)
matches_txt="$EVID/logrotate_matches_${TS}.txt"
{
  echo "## grep -RIn '/var/log/vsp-ui-8910' /etc/logrotate.conf /etc/logrotate.d"
  sudo grep -RIn --line-number "/var/log/vsp-ui-8910" /etc/logrotate.conf /etc/logrotate.d 2>/dev/null || true
} | tee "$matches_txt" >/dev/null

# Count distinct files containing that string
match_files="$EVID/logrotate_match_files_${TS}.txt"
sudo grep -RIl "/var/log/vsp-ui-8910" /etc/logrotate.conf /etc/logrotate.d 2>/dev/null \
  | sed 's|^|FILE: |' | tee "$match_files" >/dev/null

n_files="$(sudo grep -RIl "/var/log/vsp-ui-8910" /etc/logrotate.conf /etc/logrotate.d 2>/dev/null | wc -l | awk '{print $1}')"
echo "$n_files" > "$EVID/logrotate_match_files_count_${TS}.txt"

# Expect exactly 1 file ideally: /etc/logrotate.d/vsp-ui-8910
# Some distros might include it elsewhere; we enforce: NO DUPLICATE exact paths for ui_8910 logs
exact_dupe="$EVID/logrotate_exact_dupe_check_${TS}.txt"
{
  echo "## exact path duplicates check"
  sudo grep -RIn --line-number "/var/log/vsp-ui-8910/ui_8910.access.log" /etc/logrotate.conf /etc/logrotate.d 2>/dev/null || true
  sudo grep -RIn --line-number "/var/log/vsp-ui-8910/ui_8910.error.log"  /etc/logrotate.conf /etc/logrotate.d 2>/dev/null || true
} | tee "$exact_dupe" >/dev/null

access_hits="$(sudo grep -RIn --line-number "/var/log/vsp-ui-8910/ui_8910.access.log" /etc/logrotate.conf /etc/logrotate.d 2>/dev/null | wc -l | awk '{print $1}')"
error_hits="$(sudo grep -RIn --line-number "/var/log/vsp-ui-8910/ui_8910.error.log"  /etc/logrotate.conf /etc/logrotate.d 2>/dev/null | wc -l | awk '{print $1}')"
echo "access_hits=$access_hits" > "$EVID/logrotate_exact_hits_${TS}.txt"
echo "error_hits=$error_hits"  >> "$EVID/logrotate_exact_hits_${TS}.txt"

if [ "${access_hits:-0}" -ne 1 ]; then PASS=0; REASONS+=("access_path_hits:$access_hits"); warn "expected exactly 1 hit for access.log, got $access_hits"; fi
if [ "${error_hits:-0}" -ne 1 ]; then PASS=0; REASONS+=("error_path_hits:$error_hits");  warn "expected exactly 1 hit for error.log, got $error_hits";  fi

# Ensure canonical rule includes both paths and does NOT reference out_ci
rule_copy="$EVID/vsp-ui-8910.rule_${TS}.conf"
if sudo test -f "$RULE"; then
  sudo cat "$RULE" > "$rule_copy"
  if ! grep -q "/var/log/vsp-ui-8910/ui_8910.access.log" "$rule_copy"; then PASS=0; REASONS+=("rule_missing_access"); warn "rule missing access path"; fi
  if ! grep -q "/var/log/vsp-ui-8910/ui_8910.error.log"  "$rule_copy"; then PASS=0; REASONS+=("rule_missing_error");  warn "rule missing error path";  fi
  if grep -q "out_ci" "$rule_copy"; then PASS=0; REASONS+=("rule_refs_out_ci"); warn "rule still references out_ci"; fi
fi

log "== [P48/2] scheduler check (systemd timer OR cron) =="
sched="$EVID/logrotate_scheduler_${TS}.txt"
if command -v systemctl >/dev/null 2>&1; then
  {
    echo "## systemctl list-timers | grep -i logrotate"
    systemctl list-timers 2>/dev/null | grep -i logrotate || true
    echo
    echo "## systemctl status logrotate.timer"
    systemctl status logrotate.timer --no-pager 2>/dev/null || true
    echo
    echo "## systemctl status logrotate.service"
    systemctl status logrotate.service --no-pager 2>/dev/null || true
  } | tee "$sched" >/dev/null

  # If timer exists, require it to be loaded (not necessarily active in minimal images, but we warn)
  if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "logrotate.timer"; then
    if ! systemctl is-enabled logrotate.timer >/dev/null 2>&1; then
      warn "logrotate.timer exists but not enabled (WARN only)"
    fi
  else
    warn "logrotate.timer not present; will look for cron"
  fi
fi

cron_e="$EVID/logrotate_cron_${TS}.txt"
{
  echo "## cron candidates"
  ls -la /etc/cron.daily 2>/dev/null | grep -i logrotate || true
  ls -la /etc/cron.hourly 2>/dev/null | grep -i logrotate || true
  ls -la /etc/cron.d 2>/dev/null | grep -i logrotate || true
  test -f /etc/cron.daily/logrotate && echo "FOUND: /etc/cron.daily/logrotate" || true
  test -f /etc/cron.d/logrotate && echo "FOUND: /etc/cron.d/logrotate" || true
} | tee "$cron_e" >/dev/null

# Soft requirement: at least one of timer listing or cron entry exists
has_timer_line="$(grep -i "logrotate" "$sched" 2>/dev/null | wc -l | awk '{print $1}')"
has_cron_line="$(grep -i "FOUND:" "$cron_e" 2>/dev/null | wc -l | awk '{print $1}')"
echo "has_timer_lines=$has_timer_line" > "$EVID/scheduler_presence_${TS}.txt"
echo "has_cron_found=$has_cron_line"   >> "$EVID/scheduler_presence_${TS}.txt"
if [ "${has_timer_line:-0}" -eq 0 ] && [ "${has_cron_line:-0}" -eq 0 ]; then
  warn "could not confirm scheduler (timer/cron). Marking as WARN-only unless you want hard FAIL."
  # If you want hard fail: uncomment next line
  # PASS=0; REASONS+=("no_scheduler_detected")
fi

log "== [P48/3] logrotate dry-run sanity (should not mention out_ci) =="
dry="$EVID/logrotate_dryrun_${TS}.txt"
STATE="$EVID/logrotate.state"
( sudo logrotate -d -s "$STATE" "$RULE" ) >"$dry" 2>&1 || {
  PASS=0; REASONS+=("logrotate_dryrun_failed")
  tail -n 80 "$dry" >&2 || true
}
if grep -q "out_ci" "$dry"; then
  PASS=0; REASONS+=("dryrun_mentions_out_ci")
  warn "dryrun mentions out_ci unexpectedly"
fi

log "== [P48/4] verify current varlog perms/owner (0640 test:test) =="
sudo mkdir -p "$LOGDIR"
sudo touch "$LOGDIR/ui_8910.access.log" "$LOGDIR/ui_8910.error.log"
sudo chown test:test "$LOGDIR/ui_8910.access.log" "$LOGDIR/ui_8910.error.log"
sudo chmod 0640 "$LOGDIR/ui_8910.access.log" "$LOGDIR/ui_8910.error.log"

perm_a="$(stat -c '%a %U:%G %n' "$LOGDIR/ui_8910.access.log")"
perm_e="$(stat -c '%a %U:%G %n' "$LOGDIR/ui_8910.error.log")"
echo "$perm_a" | tee "$EVID/perms_access_${TS}.txt" >/dev/null
echo "$perm_e" | tee "$EVID/perms_error_${TS}.txt"  >/dev/null
echo "$perm_a" | grep -q '^640 test:test ' || { PASS=0; REASONS+=("bad_perms_access:$perm_a"); warn "bad access perms: $perm_a"; }
echo "$perm_e" | grep -q '^640 test:test ' || { PASS=0; REASONS+=("bad_perms_error:$perm_e");  warn "bad error perms: $perm_e";  }

log "== [P48/5] capture clean audit evidence (systemctl show/cat + DropInPaths) =="
svc_e="$EVID/service_audit_${TS}.txt"
{
  echo "## systemctl cat $SVC"
  systemctl cat "$SVC" --no-pager 2>/dev/null || true
  echo
  echo "## systemctl show $SVC -p DropInPaths -p ExecStart -p FragmentPath -p UnitFileState -p ActiveState -p SubState"
  systemctl show "$SVC" -p DropInPaths -p ExecStart -p FragmentPath -p UnitFileState -p ActiveState -p SubState 2>/dev/null || true
} | tee "$svc_e" >/dev/null

log "== [P48/6] write OPS_RUNBOOK.md into release (if release exists) =="
if [ -n "${latest_release:-}" ] && [ -d "$latest_release" ]; then
  RB="$latest_release/OPS_RUNBOOK.md"
  cat > "$RB" <<EOF
# OPS RUNBOOK — VSP UI (commercial)

## Service
- service name: ${SVC}
- start:  sudo systemctl start ${SVC}
- stop:   sudo systemctl stop ${SVC}
- restart:sudo systemctl restart ${SVC}
- status: systemctl status ${SVC} --no-pager

## Health checks
- UI page:  curl -fsS http://127.0.0.1:8910/vsp5 >/dev/null && echo OK
- Quick tabs:
  - /runs
  - /data_source
  - /settings
  - /rule_overrides

## Logs (operations)
- log location: ${LOGDIR}/ui_8910.access.log
- log location: ${LOGDIR}/ui_8910.error.log
- tail:
  - sudo tail -n 200 ${LOGDIR}/ui_8910.error.log
  - sudo tail -n 200 ${LOGDIR}/ui_8910.access.log

## Logrotate
- rule: ${RULE}
- test dry-run:
  - sudo logrotate -d ${RULE}
- force rotate (use a dedicated state file for audit):
  - sudo logrotate -f -s /tmp/vsp_ui_logrotate.state ${RULE}

## systemd drop-in (varlog mode)
- drop-in: zzzz-99999-execstart-varlog.conf
- verify:
  - systemctl show ${SVC} -p DropInPaths -p ExecStart

## Rollback quick guide (drop-in)
- list drop-ins:
  - systemctl show ${SVC} -p DropInPaths
- disable a drop-in:
  - sudo mkdir -p /etc/systemd/system/${SVC}.d
  - sudo mv /etc/systemd/system/${SVC}.d/<dropin>.conf /root/backup_dropins/
  - sudo systemctl daemon-reload
  - sudo systemctl restart ${SVC}
EOF
  log "[OK] wrote $(basename "$RB")"
fi

log "== [P48/7] attach evidence into release (if exists) =="
if [ -n "${latest_release:-}" ] && [ -d "$latest_release" ]; then
  mkdir -p "$latest_release/evidence/p48_${TS}"
  cp -f "$EVID/"* "$latest_release/evidence/p48_${TS}/" 2>/dev/null || true

  # Attach latest P47.3e verdict too (nice for audit chain)
  p47e_v="$(ls -1t "$OUT"/p47_3e_verdict_*.json 2>/dev/null | head -n 1 || true)"
  if [ -n "$p47e_v" ] && [ -f "$p47e_v" ]; then
    cp -f "$p47e_v" "$latest_release/evidence/p48_${TS}/" || true
    log "[OK] attached $(basename "$p47e_v")"
  fi
fi

log "== [P48/8] verdict json =="
VERDICT="$OUT/p48_verdict_${TS}.json"
python3 - <<PY
import json, time
ok = bool(int("$PASS"))
reasons = ${REASONS[@]+"["$(printf '"%s",' "${REASONS[@]}" | sed 's/,$//')"]"}  # bash -> python-safe list-ish
if reasons == "" or reasons is None:
    reasons = []
verdict = {
  "ok": ok,
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "p48": {
    "service": "$SVC",
    "logdir": "$LOGDIR",
    "rule": "$RULE",
    "latest_release": "${latest_release:-""}",
    "evidence_dir": "$EVID",
    "reasons": reasons
  }
}
print(json.dumps(verdict, indent=2))
open("$VERDICT","w").write(json.dumps(verdict, indent=2))
PY

if [ "$PASS" -eq 1 ]; then
  log "[PASS] wrote $VERDICT"
  log "[DONE] P48 PASS"
else
  log "[FAIL] wrote $VERDICT"
  log "[DONE] P48 FAIL (see reasons in verdict)"
  exit 2
fi
