#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT=out_ci; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_fix_log_perms_v2_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need date; need stat; need sudo; need chmod; need ls; need head
command -v lsattr >/dev/null 2>&1 || true
command -v getfacl >/dev/null 2>&1 || true
command -v setfacl >/dev/null 2>&1 || true

echo "== [P47.1b v2] fix ui_8910 log perms -> 0640 (no +x) ==" | tee "$LOG"

targets=()
for g in out_ci/ui_8910.error.log out_ci/ui_8910.access.log out_ci/ui_8910.error.log* out_ci/ui_8910.access.log*; do
  for f in $g; do [ -f "$f" ] && targets+=("$f"); done
done
echo "[INFO] targets=${#targets[@]}" | tee -a "$LOG"

show(){
  for f in "${targets[@]}"; do
    printf "%s %s\n" "$(stat -c '%a %U:%G' "$f")" "$f"
  done | sort
}

echo "== before ==" | tee -a "$LOG"
show | tee -a "$LOG" >/dev/null

fail=0
for f in "${targets[@]}"; do
  echo "-- $f" | tee -a "$LOG"
  # remove immutable if any
  if command -v lsattr >/dev/null 2>&1; then
    a="$(lsattr -d "$f" 2>/dev/null || true)"
    echo "lsattr: $a" | tee -a "$LOG"
    echo "$a" | grep -q ' i ' && { echo "[WARN] immutable -> chattr -i" | tee -a "$LOG"; sudo chattr -i "$f" | tee -a "$LOG"; } || true
  fi
  # clear ACL if any (best effort)
  if command -v getfacl >/dev/null 2>&1 && command -v setfacl >/dev/null 2>&1; then
    if getfacl "$f" 2>/dev/null | grep -q '^user:\|^group:'; then
      echo "[INFO] acl present -> setfacl -b" | tee -a "$LOG"
      sudo setfacl -b "$f" | tee -a "$LOG" || true
    fi
  fi
  # force perms
  sudo chmod a-x "$f" | tee -a "$LOG"
  sudo chmod 0640 "$f" | tee -a "$LOG"
  m="$(stat -c '%a' "$f")"
  echo "mode_now=$m" | tee -a "$LOG"
  [ "$m" = "640" ] || { echo "[WARN] still not 640" | tee -a "$LOG"; fail=1; }
done

echo "== after ==" | tee -a "$LOG"
show | tee -a "$LOG" >/dev/null

if [ "$fail" -eq 0 ]; then
  echo "[OK] DONE: all 0640" | tee -a "$LOG"
else
  echo "[FAIL] DONE with warnings (see $LOG)" | tee -a "$LOG"
  exit 2
fi
