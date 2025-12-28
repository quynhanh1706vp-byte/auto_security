#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p483k_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "${F}.bak_p483k_${TS}"
echo "[OK] backup => ${F}.bak_p483k_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P483K_RUNS_V3_ALIAS_ITEMS_FROM_RUNS"
if MARK in s:
    print("[OK] already patched P483k"); raise SystemExit(0)

# Heuristic: find the first JSON parse line in the vicinity of "runs_v3"
idx = s.find("runs_v3")
if idx < 0:
    # fallback: still patch the first "await r.json()" occurrence globally
    idx = 0

tail = s[idx: idx+200000]  # big slice
m = re.search(r'(\b[A-Za-z_]\w*)\s*=\s*await\s+([A-Za-z_]\w*)\.json\(\)\s*;', tail)
if not m:
    m = re.search(r'(\b[A-Za-z_]\w*)\s*=\s*await\s+([A-Za-z_]\w*)\.json\(\)\s*', tail)
if not m:
    raise SystemExit("[ERR] cannot find `X = await Y.json()` to inject alias")

var = m.group(1)
# compute absolute insert position: end of match in original string
abs_pos = idx + m.end(0)

inject = f"""
// {MARK}: commercial contract shim
try {{
  if ({var} && !Array.isArray({var}.items) && Array.isArray({var}.runs)) {var}.items = {var}.runs;
  if ({var} && typeof {var}.total === "undefined" && Array.isArray({var}.items)) {var}.total = {var}.items.length;
}} catch (e) {{}}
"""

s2 = s[:abs_pos] + inject + s[abs_pos:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected P483k alias shim near runs_v3 json parse; var =", var)
PY

if [ "${HAS_NODE:-0}" = "1" ]; then
  node --check "$F" >/dev/null 2>&1 || { echo "[ERR] node --check failed" | tee -a "$OUT/log.txt"; exit 2; }
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" 2>/dev/null || true
systemctl is-active "$SVC" 2>/dev/null || true

echo "[OK] P483k done. Close tab /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
