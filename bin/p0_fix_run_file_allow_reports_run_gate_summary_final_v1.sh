#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_runfileallow_gate_${TS}"
echo "[BACKUP] ${W}.bak_runfileallow_gate_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# 0) Add "reports/run_gate_summary.json" into any list that already has "run_gate_summary.json"
#    (only if it's a pure list item line, not dict key)
def add_reports_item(text: str):
    pat = re.compile(r'^([ \t]*)["\']run_gate_summary\.json["\'],\s*$', re.M)
    changed = 0
    def repl(m):
        nonlocal changed
        indent = m.group(1)
        # if already added nearby, skip
        if re.search(r'^\s*["\']reports/run_gate_summary\.json["\'],\s*$', text[m.start():m.start()+200], re.M):
            return m.group(0)
        changed += 1
        return m.group(0) + "\n" + f'{indent}"reports/run_gate_summary.json",'
    out = pat.sub(repl, text)
    return out, changed

s, n_add = add_reports_item(s)

# 1) Patch the run_file_allow handler region(s)
#    We locate windows around "/api/vsp/run_file_allow" and patch defensively inside.
lines = s.splitlines(True)

route_idxs = [i for i,l in enumerate(lines) if "/api/vsp/run_file_allow" in l]
patched_regions = 0
insert_force = 0
patched_if_notin = 0
patched_reports_deny = 0

for idx in route_idxs:
    # take a window around the route
    start = max(0, idx-120)
    end   = min(len(lines), idx+520)

    window = lines[start:end]
    wtxt = "".join(window)

    # find a line that assigns path from request.args.get("path")
    if "__vsp_force_allow_reports_gate" not in wtxt:
        for j in range(len(window)):
            l = window[j]
            if re.search(r'\bpath\s*=\s*.*request\.args\.get\(\s*[\'"]path[\'"]\s*\)', l):
                indent = re.match(r'^(\s*)', l).group(1)
                ins = indent + '__vsp_force_allow_reports_gate = (path == "reports/run_gate_summary.json")\n'
                # insert right after assignment
                window.insert(j+1, ins)
                insert_force += 1
                break

    # patch: if <rel|path> not in <ALLOWVAR>:
    for j in range(len(window)):
        l = window[j]
        m = re.match(r'^(\s*)if\s+(rel|path)\s+not\s+in\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*$', l)
        if m:
            indent, var, allowv = m.group(1), m.group(2), m.group(3)
            if "__vsp_force_allow_reports_gate" in l:
                continue
            window[j] = f'{indent}if {var} not in {allowv} and (not __vsp_force_allow_reports_gate):\n'
            patched_if_notin += 1

    # patch: if rel.startswith("reports/"):  -> add guard
    for j in range(len(window)):
        l = window[j]
        m = re.match(r'^(\s*)if\s+rel\.startswith\(\s*[\'"]reports/[\'"]\s*\)\s*:\s*$', l)
        if m and "not __vsp_force_allow_reports_gate" not in l:
            indent = m.group(1)
            window[j] = f'{indent}if rel.startswith("reports/") and (not __vsp_force_allow_reports_gate):\n'
            patched_reports_deny += 1

    # write back window
    lines[start:end] = window
    patched_regions += 1

s2 = "".join(lines)

if s2 == orig:
    print("[WARN] no changes applied (already patched?)")
else:
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] patched: allow_add_lines={n_add}, route_regions={patched_regions}, "
          f"insert_force={insert_force}, if_notin_patched={patched_if_notin}, reports_deny_patched={patched_reports_deny}")
PY

echo "== py_compile =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" || true
sleep 0.8

echo "== sanity =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print(j["items"][0]["run_id"])
PY
)"
echo "[RID]=$RID"

# should be 200 (or 404 file-not-found), but NOT 403 not-allowed
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 40
echo "[DONE] Hard reload /runs (Ctrl+Shift+R)."
