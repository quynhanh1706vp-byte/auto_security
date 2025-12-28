#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p482e_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

BK="${F}.bak_p482e_${TS}"
cp -f "$F" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re, sys

p = Path("static/js/vsp_c_runs_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P482E_FIX_KEPT_KEEP_APPEND_TO_PUSH_V1"
if MARK in s:
    print("[OK] already patched")
    sys.exit(0)

# patch only kept.append( / keep.append(  (không đụng DOM .append())
s2, n1 = re.subn(r'\bkept\s*\.\s*append\s*\(', 'kept.push(', s)
s2, n2 = re.subn(r'\bkeep\s*\.\s*append\s*\(', 'keep.push(', s2)

if (n1 + n2) == 0:
    print("[ERR] no kept.append( or keep.append( found. Showing nearby hints:")
    for pat in ["kept.append", "keep.append", ".append("]:
        if pat in s:
            i = s.index(pat)
            print("...", s[max(0,i-80):i+80].replace("\n","\\n"), "...")
    sys.exit(3)

s2 = s2 + f"\n/* {MARK} kept={n1} keep={n2} */\n"
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched: kept.append->push={n1}, keep.append->push={n2}")
PY

if command -v node >/dev/null 2>&1; then
  if ! node --check "$F" >/dev/null 2>&1; then
    echo "[ERR] node --check failed, rollback" | tee -a "$OUT/log.txt"
    cp -f "$BK" "$F"
    node --check "$F" >/dev/null 2>&1 || true
    exit 4
  fi
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
else
  echo "[WARN] node not found; skipped node --check" | tee -a "$OUT/log.txt"
fi

if command -v sudo >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" || true
fi

echo "[OK] P482e done. Close tab /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt" | tee -a "$OUT/log.txt"
