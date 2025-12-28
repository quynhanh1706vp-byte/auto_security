#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

S="bin/p1_ui_8910_single_owner_start_v2.sh"
[ -f "$S" ] || { echo "[ERR] missing $S"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$S" "${S}.bak_trunc_logs_${TS}"
echo "[BACKUP] ${S}.bak_trunc_logs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/p1_ui_8910_single_owner_start_v2.sh")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_TRUNCATE_LOGS_BEFORE_START_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

inject = r'''
# VSP_P1_TRUNCATE_LOGS_BEFORE_START_V1
# Avoid false "not stable" due to historical error.log tails.
BOOT_LOG="out_ci/ui_8910.boot.log"
ERR_LOG="out_ci/ui_8910.error.log"
ACC_LOG="out_ci/ui_8910.access.log"
mkdir -p out_ci
: > "$BOOT_LOG" || true
: > "$ERR_LOG" || true
: > "$ACC_LOG" || true
echo "[INFO] logs truncated: $BOOT_LOG $ERR_LOG $ACC_LOG"
START_TS="$(date +%s)"
'''

# Put right before "== start gunicorn" or before the actual gunicorn launch block
m = re.search(r'^\s*echo\s+"== start gunicorn', s, flags=re.M)
if not m:
    # fallback: before "start gunicorn single-owner" banner
    m = re.search(r'^\s*echo\s+"== start gunicorn single-owner', s, flags=re.M)

if not m:
    print("[ERR] could not find start banner to inject before")
    raise SystemExit(2)

idx = m.start()
s2 = s[:idx] + inject + "\n" + s[idx:]

p.write_text(s2, encoding="utf-8")
print("[OK] injected truncate-logs block")
PY

bash -n bin/p1_ui_8910_single_owner_start_v2.sh
echo "[OK] bash -n OK"
