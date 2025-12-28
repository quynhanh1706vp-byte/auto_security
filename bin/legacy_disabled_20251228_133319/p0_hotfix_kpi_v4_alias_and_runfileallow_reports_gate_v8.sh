#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_v8_${TS}"
echo "[BACKUP] ${W}.bak_v8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# ------------------------------------------------------------
# (A) FIX 404: add /api/ui/runs_kpi_v4 alias NEXT TO where v2 is mounted
# ------------------------------------------------------------
if "runs_kpi_v4" not in s:
    # find add_url_rule line that mounts v2
    # We copy the same view function, only change URL + endpoint name.
    pat = re.compile(r'^(?P<indent>\s*)(?P<obj>\w+)\.add_url_rule\(\s*(?P<q>["\'])/api/ui/runs_kpi_v2(?P=q)\s*,\s*(?P<q2>["\'])(?P<ep>[^"\']+)(?P=q2)\s*,\s*(?P<fn>[^,\)]+)', re.M)
    m = pat.search(s)
    if m:
        indent = m.group("indent")
        obj = m.group("obj")
        q = m.group("q")
        q2 = m.group("q2")
        ep = m.group("ep")
        fn = m.group("fn").strip()
        # create a safe endpoint name for v4
        ep_v4 = ep.replace("v2", "v4") if "v2" in ep else (ep + "_v4")
        alias_line = f'{indent}{obj}.add_url_rule({q}/api/ui/runs_kpi_v4{q}, {q2}{ep_v4}{q2}, {fn}, methods=["GET"])  # VSP_P0_KPI_V4_ALIAS_V8\n'
        # insert right after the v2 mount line
        insert_at = m.end()
        # find end of that line
        line_end = s.find("\n", insert_at)
        if line_end == -1:
            line_end = insert_at
        s = s[:line_end+1] + alias_line + s[line_end+1:]
        print("[OK] added /api/ui/runs_kpi_v4 alias next to v2 mount")
    else:
        print("[WARN] cannot find add_url_rule('/api/ui/runs_kpi_v2', ...) to alias v4 (skip)")

# ------------------------------------------------------------
# (B) FIX 403: inject reports/run_gate_summary.json into REAL allow blocks
# Strategy: find "allow clusters" that contain these tokens together:
#   SUMMARY.txt + reports/findings_unified.zip + run_gate_summary.json
# then insert reports/run_gate.json and reports/run_gate_summary.json
# right after run_gate_summary.json line (same indentation).
# ------------------------------------------------------------
lines = s.splitlines(True)
anchors = []
for i, line in enumerate(lines):
    if "SUMMARY.txt" in line:
        anchors.append(i)

added = 0
changed_blocks = 0

def has_token(win, tok):
    return any(tok in x for x in win)

for i0 in anchors:
    win = lines[i0:i0+140]  # allow-list blocks are usually within this
    if not (has_token(win, 'reports/findings_unified.zip') and has_token(win, 'run_gate_summary.json')):
        continue

    # Avoid patching non-allow contexts by requiring multiple known tokens:
    must = [
        "SUMMARY.txt",
        "findings_unified.json",
        "findings_unified.sarif",
        "reports/findings_unified.csv",
        "reports/findings_unified.html",
        "reports/findings_unified.tgz",
        "reports/findings_unified.zip",
        "run_gate.json",
        "run_gate_summary.json",
    ]
    if sum(1 for t in must if has_token(win, t)) < 7:
        continue

    # locate run_gate_summary.json line inside window
    idx = None
    for j, l in enumerate(win):
        if "run_gate_summary.json" in l:
            idx = i0 + j
            break
    if idx is None:
        continue

    block_text = "".join(win)
    if "reports/run_gate_summary.json" in block_text:
        continue

    # indent = leading whitespace of that line
    m = re.match(r'^(\s*)', lines[idx])
    indent = m.group(1) if m else ""
    # determine quote style used in that line
    q = '"' if '"' in lines[idx] else "'"

    ins = []
    ins.append(f"{indent}{q}reports/run_gate.json{q},  # VSP_P0_ALLOW_REPORTS_GATE_V8\n")
    ins.append(f"{indent}{q}reports/run_gate_summary.json{q},  # VSP_P0_ALLOW_REPORTS_GATE_V8\n")

    # insert right after idx line
    lines[idx+1:idx+1] = ins
    added += len(ins)
    changed_blocks += 1

# write back if changed
s2 = "".join(lines)
if s2 != orig:
    p.write_text(s2, encoding="utf-8")
print(f"[OK] allowlist injection: changed_blocks={changed_blocks} added_lines={added}")

PY

echo "== [CHECK] py_compile =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [CHECK] import sanity (runtime) =="
python3 - <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("wsgi_vsp_ui_gateway", "wsgi_vsp_ui_gateway.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print("[OK] import OK; app symbols:", [x for x in ("app","application") if hasattr(m,x)])
PY

echo "== restart =="
systemctl restart "$SVC" || true
sleep 1.0

echo "== wait service =="
for i in 1 2 3 4 5 6 7 8; do
  if curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null 2>&1; then
    echo "[OK] /api/vsp/runs up"
    break
  fi
  sleep 0.6
done

echo "== sanity 1: KPI v4 should be reachable now =="
curl -sS -i "$BASE/api/ui/runs_kpi_v4?days=14" | head -n 20

echo "== sanity 2: run_file_allow should allow reports/run_gate_summary.json (NOT 403 not-allowed) =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["run_id"])')"
echo "[RID]=$RID"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 40

echo "[DONE] Hard reload /runs (Ctrl+Shift+R) and check console: 403 spam should stop; KPI v4 should not 404."
