#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_runfileallow_reports_gate_v4_${TS}"
echo "[BACKUP] ${W}.bak_runfileallow_reports_gate_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# ------------------------------------------------------------
# [A] remove the misplaced snippet inside _vsp_api_404
# ------------------------------------------------------------
marker = "VSP_P0_STRIP_REPORTS_GATE_IN_RUN_FILE_ALLOW_V2"
if marker in s:
    # remove the whole injected block (marker line + following 7 lines)
    s = re.sub(
        r'^\s*#\s*VSP_P0_STRIP_REPORTS_GATE_IN_RUN_FILE_ALLOW_V2.*\n'
        r'(?:^\s*#.*\n)?'
        r'(?:^\s*try:\n)?'
        r'(?:.*\n){0,12}?',
        '',
        s,
        flags=re.M
    )

# ------------------------------------------------------------
# [B] add allow entries for reports/run_gate*.json
# We patch ALL allow lists that already contain run_gate_summary.json
# and are part of the run_file_allow response allow[] (your 403 shows that list).
# ------------------------------------------------------------
lines = s.splitlines(True)

def insert_after_token(lines, token, new_items):
    changed = 0
    for i in range(len(lines)-1, -1, -1):
        if token in lines[i]:
            # only if we're inside a list literal-ish area (line contains quotes and comma)
            if '"' in lines[i] and "," in lines[i]:
                # avoid duplicates: check a small window around
                window = "".join(lines[max(0,i-30):min(len(lines), i+30)])
                for item in new_items:
                    if item in window:
                        continue
                    indent = re.match(r'^(\s*)', lines[i]).group(1)
                    lines.insert(i+1, f'{indent}"{item}",\n')
                    changed += 1
    return changed

chg = 0
chg += insert_after_token(lines, '"run_gate_summary.json"', ["reports/run_gate_summary.json"])
chg += insert_after_token(lines, '"run_gate.json"', ["reports/run_gate.json"])

s2 = "".join(lines)

p.write_text(s2, encoding="utf-8")
print(f"[OK] wrote wsgi. allow_add={chg}, removed_misplaced={(marker in orig)}")
PY

python3 -m py_compile "$W" && echo "[OK] py_compile OK"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

RID="RUN_20251120_130310"
echo "== sanity (should be 200 now) =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 80

echo "== sanity allowlist now contains reports/run_gate_summary.json =="
curl -sS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -c 400; echo
