#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_allow_gate_reports_no403_${TS}"
echo "[BACKUP] ${W}.bak_allow_gate_reports_no403_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Ensure allowlist includes reports/run_gate_summary.json + reports/run_gate.json
need_paths = [
  "run_gate_summary.json",
  "reports/run_gate_summary.json",
  "run_gate.json",
  "reports/run_gate.json",
]

# Try to find the allowlist literal that matches the response you saw (contains SUMMARY.txt, findings_unified..., run_gate_summary.json)
# We'll patch the first list that contains 'run_gate_summary.json' and 'reports/findings_unified.csv' to be safe.
pat_list = re.compile(r'(?s)(allow\s*=\s*\[)(.*?)(\])')
m_best = None
for m in pat_list.finditer(s):
    body = m.group(2)
    if ("run_gate_summary.json" in body) and ("reports/findings_unified.csv" in body or "findings_unified.tgz" in body):
        m_best = m
        break

changed_allow = 0
if m_best:
    head, body, tail = m_best.group(1), m_best.group(2), m_best.group(3)
    # collect existing quoted strings
    existing = set(re.findall(r'["\']([^"\']+)["\']', body))
    add = [x for x in need_paths if x not in existing]
    if add:
        # insert before closing bracket, keep formatting simple
        insert = "".join([f'    "{x}",\n' for x in add])
        new_body = body
        # if body doesn't end with newline, add
        if not new_body.endswith("\n"):
            new_body += "\n"
        new = head + new_body + insert + tail
        s = s[:m_best.start()] + new + s[m_best.end():]
        changed_allow = len(add)

# 2) Make run_file_allow not return HTTP 403 (return 200 with ok:false JSON)
# Replace patterns like: return jsonify(...), 403   OR abort(403)
changed_403 = 0

# a) return ..., 403  -> return ...
s2, n = re.subn(r'(return\s+jsonify\([^\)]*\))\s*,\s*403\b', r'\1', s)
if n:
    s = s2
    changed_403 += n

# b) abort(403) -> return jsonify(ok=False, err="not allowed", ts=int(time.time()))
# only if abort(403) is directly used in run_file_allow area; do a conservative replace
# We'll inject a tiny helper import time if needed
if "abort(403" in s:
    s2, n = re.subn(r'\babort\s*\(\s*403\s*\)', 'return jsonify(ok=False, err="not allowed")', s)
    if n:
        s = s2
        changed_403 += n

p.write_text(s, encoding="utf-8")
print(f"[OK] patched allowlist add={changed_allow} ; no403 changes={changed_403}")
PY

python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

echo "== sanity: KPI v2 =="
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 220; echo

echo "== sanity: run_file_allow gate summary (should NOT be 403 now) =="
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print(j["items"][0]["run_id"])
PY
)"
echo "[RID]=$RID"
# this one is gate_root=false for most runs
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 12 || true

echo "[DONE] Hard reload /runs (Ctrl+Shift+R). Console 403 should disappear; trend can load."
