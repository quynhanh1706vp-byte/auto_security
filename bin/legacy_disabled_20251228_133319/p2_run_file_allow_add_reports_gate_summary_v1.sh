#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_allow_reports_gate_${TS}"
echo "[BACKUP] ${W}.bak_allow_reports_gate_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) locate the allowlist that contains run_gate_summary.json (from your error JSON)
# We'll inject 'reports/run_gate_summary.json' and 'reports/run_gate.json' near it.
need = ["reports/run_gate_summary.json", "reports/run_gate.json"]

if all(x in s for x in need):
    print("[OK] allowlist already contains reports/* gate files")
    raise SystemExit(0)

# Prefer to patch the first allow-list literal that includes "run_gate_summary.json"
# Common patterns: allow = [ ... ] or ALLOW = set([...])
pat = re.compile(r'(?s)("allow"\s*:\s*\[.*?\])')  # sometimes allow is in response; not reliable
# Better: find any bracket list that includes run_gate_summary.json
cand = None
for m in re.finditer(r'(?s)(\[[^\]]*?"run_gate_summary\.json"[^\]]*?\])', s):
    cand = m
    break

if not cand:
    # fallback: look for set(...) containing run_gate_summary.json
    for m in re.finditer(r'(?s)(set\(\s*\[[^\]]*?"run_gate_summary\.json"[^\]]*?\]\s*\))', s):
        cand = m
        break

if not cand:
    print("[ERR] cannot locate allowlist containing run_gate_summary.json")
    raise SystemExit(2)

block = cand.group(1)

def inject(block:str)->str:
    out = block
    for item in need:
        if item in out:
            continue
        # insert right after "run_gate_summary.json"
        out = re.sub(r'("run_gate_summary\.json"\s*,?)', r'\1\n  "'+item+'",', out, count=1)
    # cleanup double commas like ",,"
    out = re.sub(r',\s*,', ',', out)
    return out

new_block = inject(block)
if new_block == block:
    print("[WARN] no changes applied (already patched?)")
else:
    s2 = s.replace(block, new_block, 1)
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched allowlist: added reports/run_gate_summary.json + reports/run_gate.json")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "[INFO] restarting service..."
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.7

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="RUN_20251120_130310"
echo "== sanity: should be allowed now =="
curl -sS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -c 220; echo

echo "[DONE] Hard reload /runs (Ctrl+Shift+R). 403 hết -> trend sẽ lên."
