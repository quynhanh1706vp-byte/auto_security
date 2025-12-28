#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p560_${TS}"
mkdir -p "$OUT"

log(){ echo "$*" | tee -a "$OUT/run.log"; }

log "== [P560] lock ship layout TS=$TS =="

mkdir -p bin/legacy

# 1) Move bin/p*.sh to bin/legacy (keep history)
moved=0
for f in bin/p*.sh; do
  [ -e "$f" ] || continue
  bn="$(basename "$f")"
  # keep any existing legacy file with suffix
  dest="bin/legacy/${bn}"
  if [ -e "$dest" ]; then
    dest="bin/legacy/${bn}.dup_${TS}"
  fi
  mv -f "$f" "$dest"
  chmod -x "$dest" || true
  moved=$((moved+1))
  log "[OK] moved $f => $dest (chmod -x)"
done

if [ "$moved" -eq 0 ]; then
  log "[INFO] no bin/p*.sh found to move"
fi

# 2) Safety: remove exec bit for anything under legacy
find bin/legacy -type f -maxdepth 2 -exec chmod -x {} \; 2>/dev/null || true

# 3) List remaining executables under bin (audit)
find bin -maxdepth 2 -type f -perm -111 | sed 's|^\./||' | sort > "$OUT/bin_executables_after.txt"
log "[OK] wrote $OUT/bin_executables_after.txt"

# 4) Ensure 4 entrypoints are executable
for f in ui_gate.sh verify_release_and_customer_smoke.sh pack_release.sh ops.sh; do
  if [ -f "bin/$f" ]; then
    chmod +x "bin/$f" || true
    log "[OK] ensure executable: bin/$f"
  else
    log "[WARN] missing entrypoint: bin/$f"
  fi
done

log "== [P560] done =="
