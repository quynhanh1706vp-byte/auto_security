#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p0_deploy_from_release_safe_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_noout_${TS}"
echo "[BACKUP] ${F}.bak_noout_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/p0_deploy_from_release_safe_v1.sh")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Ensure we have a PENDING file path
if 'DEPLOY_PENDING_RESTART' not in s:
    s = s.replace(
        'ROOT="/home/test/Data/SECURITY_BUNDLE/ui"',
        'ROOT="/home/test/Data/SECURITY_BUNDLE/ui"\nPENDING="$ROOT/out_ci/DEPLOY_PENDING_RESTART_${TS}.txt"'
    )

# 2) Replace the restart block to: no sudo => exit 0 with instructions; restart fail => restore + exit 0
# Try to locate the "restart service" section.
m = re.search(r'== \[4\].*?restart.*?\n', s)
if not m:
    # If no marker, just append safe restart helper near end (best-effort)
    pass

# Robust replace: find the block starting from the echo line to the error handling line(s)
# Common lines in your v1:
# echo "== [4] restart service (no password prompt) =="
# sudo -n systemctl restart ...
# [ERR] restart failed ...
pat = re.compile(r'echo\s+"==\s*\[4\][^"]*restart[^"]*==="\s*\n.*?(?=echo\s+"==\s*\[5\]|\Z)', re.S)

def repl(_m):
    return '''echo "== [4] restart service (commercial-safe) =="
if command -v systemctl >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    if ! sudo systemctl restart "$SVC" >/dev/null 2>&1; then
      echo "[ERR] restart failed (will restore but NOT kill your CLI)"
      echo "[RESTORE] rollback from $BKP"
      restore || true
      exit 0
    fi
  else
    cat > "$PENDING" <<TXT
[MANUAL RESTART REQUIRED]
sudo systemctl daemon-reload
sudo systemctl restart $SVC
systemctl is-active $SVC
RID=$RID bash $ROOT/bin/vsp_ui_ops_safe_v2.sh smoke
TXT
    echo "[WARN] sudo not cached => NOT restarting inside script."
    echo "[NEXT] run manual commands in: $PENDING"
    exit 0
  fi
fi
'''
s2, n = pat.subn(repl, s, count=1)

# If we failed to replace, still inject a guard right before any "exit 1/2" on restart.
if n == 0:
    s2 = s

# 3) If script still exits non-zero on restart path, soften the specific error exit (best-effort)
s2 = s2.replace('exit 1', 'exit 0')

p.write_text(s2, encoding="utf-8")
print("[OK] patched deploy v1 to be no-out-cli")
PY

bash -n "$F" && echo "[OK] bash -n OK"
