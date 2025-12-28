#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
FILES=(static/js/vsp_tabs3_common_v3.js static/js/vsp_p0_fetch_shim_v1.js)

echo "== [0] backup =="
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
  cp -f "$f" "${f}.bak_runsfix_${TS}"
  echo "[BACKUP] ${f}.bak_runsfix_${TS}"
done

echo "== [1] patch False->false and runs?limit=10->1 =="
python3 - <<'PY'
from pathlib import Path
import re

files = [
  Path("static/js/vsp_tabs3_common_v3.js"),
  Path("static/js/vsp_p0_fetch_shim_v1.js"),
]

def patch_text(s: str):
  n_false = 0
  n_limit = 0

  # Fix Python-style booleans accidentally injected
  s2, n_false = re.subn(r'\breturn\s+False\s*;', 'return false;', s)
  s2, n_false2 = re.subn(r'\breturn\s+True\s*;', 'return true;', s2)
  n_false += n_false2

  # Fix runs limit (backend seems broken for limit>1)
  s3, n_limit = re.subn(r'"/api/vsp/runs\?limit=10"', '"/api/vsp/runs?limit=1"', s2)
  s3, n_limit2 = re.subn(r'"/api/vsp/runs\?limit=5"', '"/api/vsp/runs?limit=1"', s3)
  n_limit += n_limit2

  # Also catch single quotes variants
  s4, n_limit3 = re.subn(r"'/api/vsp/runs\?limit=10'", "'/api/vsp/runs?limit=1'", s3)
  s4, n_limit4 = re.subn(r"'/api/vsp/runs\?limit=5'", "'/api/vsp/runs?limit=1'", s4)
  n_limit += n_limit3 + n_limit4

  return s4, n_false, n_limit

total_false = 0
total_limit = 0

for p in files:
  s = p.read_text(encoding="utf-8", errors="replace")
  s2, n_false, n_limit = patch_text(s)
  if s2 != s:
    p.write_text(s2, encoding="utf-8")
  print(f"[OK] {p}: returnFalseFix={n_false} runsLimitFix={n_limit}")
  total_false += n_false
  total_limit += n_limit

print("[DONE] total returnFalseFix=", total_false, " total runsLimitFix=", total_limit)
PY

echo "== [2] node --check =="
for f in "${FILES[@]}"; do
  node --check "$f" >/dev/null && echo "[OK] node --check: $f"
done

echo "[DONE] Ctrl+F5 /data_source /rule_overrides /settings /vsp5."
