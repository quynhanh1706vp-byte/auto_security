#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_add_reports_gate_marker_${TS}"
echo "[BACKUP] ${W}.bak_add_reports_gate_marker_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

need = [
  "reports/run_gate_summary.json",
  "reports/run_gate.json",
]

if all(x in s for x in need):
    print("[OK] already contains reports gate paths (no change)")
else:
    # insert right after the first appearance of "run_gate_summary.json"
    # works whether the quote is ' or "
    def repl(m):
        token = m.group(0)
        ins = token
        for x in need:
            if x not in s:
                ins += f', "{x}"'
        return ins

    s2, n = re.subn(r'["\']run_gate_summary\.json["\']', repl, s, count=1)
    if n == 0:
        raise SystemExit("[ERR] cannot find run_gate_summary.json marker to insert after")

    p.write_text(s2, encoding="utf-8")
    print(f"[OK] inserted reports gate paths after run_gate_summary.json (n={n})")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print(j["items"][0]["run_id"])
PY
)"
echo "[RID]=$RID"

echo "-- run_file_allow reports/run_gate_summary.json --"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 40

echo "[DONE] Hard reload /runs (Ctrl+Shift+R)."
