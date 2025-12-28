#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
OUT=out_ci; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_log_perm_forensics_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need date; need stat; need ls; need sudo; need id
command -v findmnt >/dev/null 2>&1 && need findmnt || true
command -v getfacl >/dev/null 2>&1 || true
command -v lsattr >/dev/null 2>&1 || true

F="out_ci/ui_8910.error.log"
echo "== [FORensics] $TS ==" | tee "$LOG"
id | tee -a "$LOG" >/dev/null
echo "umask=$(umask)" | tee -a "$LOG"
echo "file=$F" | tee -a "$LOG"

echo "== ls/stat ==" | tee -a "$LOG"
ls -l "$F" 2>&1 | tee -a "$LOG" >/dev/null || true
stat -c '%A %a %U:%G %F %n' "$F" 2>&1 | tee -a "$LOG" >/dev/null || true

echo "== mount info ==" | tee -a "$LOG"
if command -v findmnt >/dev/null 2>&1; then
  findmnt -T "$F" -o TARGET,SOURCE,FSTYPE,OPTIONS 2>&1 | tee -a "$LOG" >/dev/null || true
fi

echo "== attrs/acl ==" | tee -a "$LOG"
if command -v lsattr >/dev/null 2>&1; then lsattr -d "$F" 2>&1 | tee -a "$LOG" >/dev/null || true; fi
if command -v getfacl >/dev/null 2>&1; then getfacl -p "$F" 2>&1 | head -n 80 | tee -a "$LOG" >/dev/null || true; fi

echo "== try chmod (with rc) ==" | tee -a "$LOG"
set +e
sudo chmod a-x "$F" 2>&1 | tee -a "$LOG" >/dev/null; rc1=${PIPESTATUS[0]}
sudo chmod 0640 "$F" 2>&1 | tee -a "$LOG" >/dev/null; rc2=${PIPESTATUS[0]}
set -e
echo "rc_chmod_ax=$rc1 rc_chmod_0640=$rc2" | tee -a "$LOG"
stat -c 'AFTER: %A %a %U:%G %F %n' "$F" 2>&1 | tee -a "$LOG" >/dev/null || true

echo "[OK] log=$LOG" | tee -a "$LOG"
