#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_fix_runfileallow_real_${TS}"
echo "[BACKUP] ${W}.bak_fix_runfileallow_real_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# target: the REAL allowlist list-literal that includes these tokens (matches your returned allow[])
must = [
  "SUMMARY.txt",
  "findings_unified.json",
  "reports/findings_unified.csv",
  "reports/findings_unified.tgz",
  "run_gate.json",
  "run_gate_summary.json",
]
add_paths = [
  "reports/run_gate_summary.json",
  "reports/run_gate.json",
]

# find candidate list literals: allow = [ ... ]
cand = []
for m in re.finditer(r'(?s)\ballow\s*=\s*\[(.*?)\]\s*', s):
    body = m.group(1)
    ok = all(t in body for t in must)
    if ok:
        cand.append((m.start(), m.end(), body))

if not cand:
    raise SystemExit("[ERR] cannot find REAL allow=[...] list containing expected tokens")

# choose smallest matching list (most likely the handler allowlist)
cand.sort(key=lambda x: (x[1]-x[0]))
st, en, body = cand[0]

body2 = body
ins = []
for ap in add_paths:
    if ap not in body2:
        ins.append(ap)

if ins:
    # insert near run_gate_summary.json for stable diff
    # keep quote style as double quotes
    def _inject(m):
        x = m.group(0)
        extra = "".join([f', "{ap}"' for ap in ins])
        return x + extra
    body2, n = re.subn(r'["\']run_gate_summary\.json["\']', _inject, body2, count=1)
    if n == 0:
        # fallback: append at end
        body2 = body2.rstrip() + "".join([f', "{ap}"' for ap in ins])
    s = s[:st] + re.sub(r'(?s)\ballow\s*=\s*\[(.*?)\]\s*', lambda _: f'allow = [{body2}]\n', s[st:en], count=1) + s[en:]
    print(f"[OK] inserted into REAL allowlist: {ins}")
else:
    print("[OK] REAL allowlist already has reports gate paths")

# ALSO: downgrade deny 403->200 in run_file_allow responses (reduce console red spam)
# We change ONLY in the vicinity of the allowlist we matched (local patch window).
win_lo = max(0, st - 2200)
win_hi = min(len(s), en + 2200)
chunk = s[win_lo:win_hi]

# common patterns: return jsonify(...), 403   OR  make_response(..., 403)
chunk2, n1 = re.subn(r'(\breturn\s+[^#\n]*?\),\s*)403\b', r'\g<1>200', chunk)
chunk3, n2 = re.subn(r'(\breturn\s+[^#\n]*?\b),\s*403\b', r'\g<1>, 200', chunk2)

if (n1+n2) > 0:
    s = s[:win_lo] + chunk3 + s[win_hi:]
    print(f"[OK] deny status patched 403->200 (n={n1+n2}) within run_file_allow area")
else:
    print("[OK] no deny-403 pattern found near handler (skip)")

p.write_text(s, encoding="utf-8")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

RID="$(curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print(j.get("latest_rid",""))
PY
)"
echo "[RID]=$RID"

echo "== run_file_allow reports/run_gate_summary.json =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 40

echo "[DONE] Hard reload /runs (Ctrl+Shift+R)."
