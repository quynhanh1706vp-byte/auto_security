#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_runs_reports_bp.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_allowsha_v2_${TS}"
echo "[BACKUP] ${F}.bak_allowsha_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_runs_reports_bp.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_BP_ALLOW_REPORTS_SHA256SUMS_P1_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Ensure FULL path is allowed (most strict check in your bp)
# Replace occurrences of reports/SUMMARY.txt in allowlist blocks to include reports/SHA256SUMS.txt
changed=False

def add_after(token):
    global s, changed
    if "reports/SHA256SUMS.txt" in s:
        return
    # add right after token inside same list/set/tuple line(s)
    # works for both '...' and "..."
    pat = re.escape(token)
    repl = token + ', "reports/SHA256SUMS.txt"'
    # try double-quote token first
    if '"' + token + '"' in s:
        s2 = s.replace(f'"{token}"', f'"{token}", "reports/SHA256SUMS.txt"', 1)
        if s2 != s:
            s = s2; changed=True; return
    # single-quote
    if "'" + token + "'" in s:
        s2 = s.replace(f"'{token}'", f"'{token}', 'reports/SHA256SUMS.txt'", 1)
        if s2 != s:
            s = s2; changed=True; return

# primary anchor: reports/SUMMARY.txt (because that one is already served 200)
add_after("reports/SUMMARY.txt")

# fallback: if bp uses basename allowlist only, also allow basename (harmless)
if "SHA256SUMS.txt" not in s:
    if '"SUMMARY.txt"' in s:
        s = s.replace('"SUMMARY.txt"', '"SUMMARY.txt", "SHA256SUMS.txt"', 1); changed=True
    elif "'SUMMARY.txt'" in s:
        s = s.replace("'SUMMARY.txt'", "'SUMMARY.txt', 'SHA256SUMS.txt'", 1); changed=True

if not changed and "reports/SHA256SUMS.txt" not in s:
    raise SystemExit("[ERR] could not patch allowlist automatically. Need to inspect allowlist definition.")

s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched allowlist for reports/SHA256SUMS.txt")
PY

python3 -m py_compile vsp_runs_reports_bp.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="btl86-connector_RUN_20251127_095755_000599"
echo "RID=$RID"
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 12
