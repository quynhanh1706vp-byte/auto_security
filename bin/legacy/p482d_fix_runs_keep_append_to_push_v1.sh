#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p482d_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

BK="${F}.bak_p482d_${TS}"
cp -f "$F" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re, sys

p = Path("static/js/vsp_c_runs_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P482D_FIX_KEEP_APPEND_TO_PUSH_V1"
if MARK in s:
    print("[OK] already patched")
    sys.exit(0)

# Fix: keep.append(...) -> keep.push(...)
s2, n = re.subn(r'\bkeep\s*\.\s*append\s*\(', 'keep.push(', s)

if n == 0:
    # still allow pass: sometimes variable name is KEEP or keepList, but console said keep.append
    print("[WARN] no keep.append( found; no changes made")
    # still stamp marker so we know we checked? no, don't.
    sys.exit(1)

s2 = s2 + f"\n/* {MARK} repl={n} */\n"
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched keep.append -> keep.push ; repl={n}")
PY

# quick syntax check if node exists
if command -v node >/dev/null 2>&1; then
  if ! node --check "$F" >/dev/null 2>&1; then
    echo "[ERR] node --check failed, rollback" | tee -a "$OUT/log.txt"
    cp -f "$BK" "$F"
    node --check "$F" >/dev/null 2>&1 || true
    exit 3
  fi
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
else
  echo "[WARN] node not found; skipped node --check" | tee -a "$OUT/log.txt"
fi

# restart (optional but keep consistent with your workflow)
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" || true
fi

echo "[OK] P482d done. Close tab /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt" | tee -a "$OUT/log.txt"
