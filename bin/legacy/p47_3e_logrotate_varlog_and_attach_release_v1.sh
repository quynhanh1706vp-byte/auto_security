#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
LOGDIR="/var/log/vsp-ui-8910"
RULE="/etc/logrotate.d/vsp-ui-8910"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p47_3e_${TS}"
mkdir -p "$OUT" "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need awk; need sed; need grep; need head; need tail; need ls; need stat; need cp; need mkdir
need logrotate
command -v systemctl >/dev/null 2>&1 || true
need sudo

log(){ echo "[$(date +%H:%M:%S)] $*"; }
fail(){ echo "[FAIL] $*" >&2; exit 1; }

log "== [P47.3e/0] prep logdir =="
sudo mkdir -p "$LOGDIR"
sudo chown test:test "$LOGDIR"
sudo chmod 0750 "$LOGDIR"

# Ensure files exist (do not change content)
sudo touch "$LOGDIR/ui_8910.access.log" "$LOGDIR/ui_8910.error.log"
sudo chown test:test "$LOGDIR/ui_8910.access.log" "$LOGDIR/ui_8910.error.log"
sudo chmod 0640 "$LOGDIR/ui_8910.access.log" "$LOGDIR/ui_8910.error.log"

log "== [P47.3e/1] backup + write canonical logrotate rule =="
if [ -f "$RULE" ]; then
  sudo cp -f "$RULE" "$EVID/vsp-ui-8910.logrotate.bak_${TS}"
  log "[OK] backup: $EVID/vsp-ui-8910.logrotate.bak_${TS}"
else
  log "[WARN] $RULE not found; will create new"
fi

# Canonical rule: rotate only /var/log (NOT out_ci)
tmp_rule="$(mktemp /tmp/vsp_ui_8910_logrotate_XXXXXX)"
cat > "$tmp_rule" <<'EOF'
/var/log/vsp-ui-8910/ui_8910.access.log
/var/log/vsp-ui-8910/ui_8910.error.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    create 0640 test test
    sharedscripts
    postrotate
        /bin/systemctl is-active vsp-ui-8910.service >/dev/null 2>&1 && /bin/systemctl kill -s USR1 vsp-ui-8910.service >/dev/null 2>&1 || true
    endscript
}
EOF

sudo cp -f "$tmp_rule" "$RULE"
rm -f "$tmp_rule"
sudo chmod 0644 "$RULE"

log "== [P47.3e/2] sanity check rule (must include /var/log and must NOT include out_ci) =="
sudo cat "$RULE" > "$EVID/vsp-ui-8910.logrotate.final_${TS}.conf"
if ! grep -q "/var/log/vsp-ui-8910/ui_8910.access.log" "$EVID/vsp-ui-8910.logrotate.final_${TS}.conf"; then
  fail "rule missing access.log path"
fi
if ! grep -q "/var/log/vsp-ui-8910/ui_8910.error.log" "$EVID/vsp-ui-8910.logrotate.final_${TS}.conf"; then
  fail "rule missing error.log path"
fi
if grep -q "out_ci" "$EVID/vsp-ui-8910.logrotate.final_${TS}.conf"; then
  fail "rule still references out_ci"
fi
log "[OK] rule paths OK"

log "== [P47.3e/3] logrotate dry-run (-d) + force (-f) with dedicated state =="
STATE="$EVID/logrotate.state"
DRY="$EVID/logrotate_dryrun_${TS}.txt"
FORCE="$EVID/logrotate_force_${TS}.txt"

# dry run
( sudo logrotate -d -s "$STATE" "$RULE" ) >"$DRY" 2>&1 || {
  tail -n 80 "$DRY" >&2
  fail "logrotate -d failed"
}
log "[OK] logrotate -d OK"

# force rotate
( sudo logrotate -f -s "$STATE" "$RULE" ) >"$FORCE" 2>&1 || {
  tail -n 80 "$FORCE" >&2
  fail "logrotate -f failed"
}
log "[OK] logrotate -f OK"

log "== [P47.3e/4] verify perms + ownership (current logs must be 0640 test:test) =="
PERM_A="$(stat -c '%a %U:%G %n' "$LOGDIR/ui_8910.access.log")"
PERM_E="$(stat -c '%a %U:%G %n' "$LOGDIR/ui_8910.error.log")"
echo "$PERM_A" | tee "$EVID/perms_access_${TS}.txt"
echo "$PERM_E" | tee "$EVID/perms_error_${TS}.txt"

echo "$PERM_A" | grep -q '^640 test:test ' || fail "bad perms/owner access: $PERM_A"
echo "$PERM_E" | grep -q '^640 test:test ' || fail "bad perms/owner error: $PERM_E"
log "[OK] perms/owner OK"

log "== [P47.3e/5] snapshot evidence (ls/stat) =="
sudo ls -la "$LOGDIR" | tee "$EVID/ls_varlog_${TS}.txt" >/dev/null
sudo find "$LOGDIR" -maxdepth 1 -type f -name 'ui_8910*.log*' -printf '%TY-%Tm-%Td %TH:%TM:%TS %p\n' \
  | sort -r | head -n 40 | tee "$EVID/top_varlog_files_${TS}.txt" >/dev/null

log "== [P47.3e/6] locate latest release + attach evidence =="
latest_release=""
if [ -d "$RELROOT" ]; then
  latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
fi

if [ -z "${latest_release:-}" ] || [ ! -d "$latest_release" ]; then
  log "[WARN] no release folder found under $RELROOT; will only keep evidence in $EVID"
else
  log "[OK] latest_release=$latest_release"
  mkdir -p "$latest_release/evidence/p47_3e_${TS}"
  cp -f "$EVID/"* "$latest_release/evidence/p47_3e_${TS}/" 2>/dev/null || true

  # Attach p47 clean varlog proof (latest)
  p47_clean="$(ls -1t "$OUT"/p47_clean_varlog_*.txt 2>/dev/null | head -n 1 || true)"
  if [ -n "$p47_clean" ] && [ -f "$p47_clean" ]; then
    cp -f "$p47_clean" "$latest_release/evidence/p47_3e_${TS}/" || true
    log "[OK] attached $(basename "$p47_clean")"
  else
    log "[WARN] no out_ci/p47_clean_varlog_*.txt found to attach"
  fi

  # Update HANDOVER.md (append two lines if missing)
  H="$latest_release/HANDOVER.md"
  if [ ! -f "$H" ]; then
    cat > "$H" <<EOF
# HANDOVER (auto-updated by P47.3e)

EOF
  fi
  grep -q '^log location: /var/log/vsp-ui-8910/\*\.log' "$H" || echo "log location: /var/log/vsp-ui-8910/*.log" >> "$H"
  grep -q '^drop-in: zzzz-99999-execstart-varlog\.conf' "$H" || echo "drop-in: zzzz-99999-execstart-varlog.conf" >> "$H"
  log "[OK] HANDOVER.md updated"
fi

log "== [P47.3e/7] verdict json =="
VERDICT="$OUT/p47_3e_verdict_${TS}.json"
python3 - <<PY
import json, os, time
verdict = {
  "ok": True,
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "p47_3e": {
    "rule": "$RULE",
    "logdir": "$LOGDIR",
    "service": "$SVC",
    "latest_release": "${latest_release:-""}",
    "evidence_dir": "$EVID"
  }
}
print(json.dumps(verdict, indent=2))
open("$VERDICT","w").write(json.dumps(verdict, indent=2))
PY
log "[PASS] wrote $VERDICT"
log "[DONE] P47.3e PASS"
