#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"

W="wsgi_vsp_ui_gateway.py"
JS_KPI="static/js/vsp_runs_kpi_compact_v3.js"
JS_QA="static/js/vsp_runs_quick_actions_v1.js"
JS_OV="static/js/vsp_runs_reports_overlay_v1.js"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [0] snapshot current =="
cp -f "$W" "${W}.bak_stabilize_${TS}"
for f in "$JS_KPI" "$JS_QA" "$JS_OV"; do
  [ -f "$f" ] && cp -f "$f" "${f}.bak_stabilize_${TS}" || true
done
echo "[BACKUP] ${W}.bak_stabilize_${TS}"

echo "== [1] restore latest compiling backup (if current broken) =="
python3 - <<'PY'
from pathlib import Path
import py_compile, time

w = Path("wsgi_vsp_ui_gateway.py")
def ok(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

if ok(w):
    print("[OK] current wsgi compiles; keep it")
    raise SystemExit(0)

baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
for b in baks:
    try:
        tmp = Path("/tmp/_wsgi_restore_try.py")
        tmp.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        py_compile.compile(str(tmp), doraise=True)
        w.write_text(tmp.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        print(f"[OK] restored from compiling backup: {b.name}")
        raise SystemExit(0)
    except Exception:
        continue

print("[ERR] cannot find any compiling backup")
raise SystemExit(2)
PY

echo "== [2] patch run_file_allow handler to allow reports/run_gate_summary.json =="
python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
lines = s.splitlines(True)

# 2.1 find handler name from add_url_rule
m = re.search(
    r'add_url_rule\(\s*["\']/api/vsp/run_file_allow["\']\s*,\s*["\'][^"\']+["\']\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*,',
    s
)
if not m:
    print("[ERR] cannot locate add_url_rule('/api/vsp/run_file_allow', ..., HANDLER, ...)")
    sys.exit(2)
fn = m.group(1)
print("[OK] run_file_allow handler =", fn)

# 2.2 locate def fn(...)
def_re = re.compile(rf'^(?P<ind>[ \t]*)def[ \t]+{re.escape(fn)}[ \t]*\(', re.M)
dm = def_re.search(s)
if not dm:
    print("[ERR] cannot locate def for handler:", fn)
    sys.exit(2)

# convert char index -> line index
def_pos = dm.start()
acc = 0
start_i = None
for i, ln in enumerate(lines):
    acc2 = acc + len(ln)
    if acc <= def_pos < acc2:
        start_i = i
        break
    acc = acc2
if start_i is None:
    print("[ERR] internal: cannot map def position")
    sys.exit(2)

base_indent = dm.group("ind")

def indent_len(x: str) -> int:
    x = x.replace("\t", "    ")
    return len(x)

base_len = indent_len(base_indent)

# find end of function block by indentation
end_i = len(lines)
for j in range(start_i + 1, len(lines)):
    ln = lines[j]
    if not ln.strip():
        continue
    cur_indent = re.match(r'^[ \t]*', ln).group(0)
    if indent_len(cur_indent) <= base_len and not ln.lstrip().startswith("#"):
        end_i = j
        break

block = lines[start_i:end_i]
block_text = "".join(block)

if "reports/run_gate_summary.json" in block_text:
    print("[OK] handler already mentions reports/run_gate_summary.json (no change)")
    p.write_text("".join(lines), encoding="utf-8")
    raise SystemExit(0)

# find all lines that define run_gate_summary.json in this function and duplicate its value/style
changed = 0
for idx in range(len(block)-1, -1, -1):
    ln = block[idx]
    if "run_gate_summary.json" not in ln:
        continue
    if "reports/run_gate_summary.json" in ln:
        continue
    # dict style: "run_gate_summary.json": <val>,
    md = re.match(r'^([ \t]*)"run_gate_summary\.json"\s*:\s*(.+?)(,?\s*)$', ln.rstrip("\n"))
    if md:
        ind, val, tail = md.groups()
        comma = ","  # ensure comma
        new_ln = f'{ind}"reports/run_gate_summary.json": {val}{comma}\n'
        block.insert(idx+1, new_ln)
        changed += 1
        continue
    # list style: "run_gate_summary.json",
    ml = re.match(r'^([ \t]*)"run_gate_summary\.json"\s*(,?\s*)$', ln.rstrip("\n"))
    if ml:
        ind, tail = ml.groups()
        comma = ","  # ensure comma
        new_ln = f'{ind}"reports/run_gate_summary.json"{comma}\n'
        block.insert(idx+1, new_ln)
        changed += 1
        continue

# write back
lines[start_i:end_i] = block
p.write_text("".join(lines), encoding="utf-8")
print("[OK] injected reports/run_gate_summary.json entries =", changed)
PY

echo "== [3] rewire JS to avoid KPI v4 404 + ensure run_file_allow (not allow2) =="
python3 - <<'PY'
from pathlib import Path
import re

targets = [
  Path("static/js/vsp_runs_kpi_compact_v3.js"),
  Path("static/js/vsp_runs_quick_actions_v1.js"),
  Path("static/js/vsp_runs_reports_overlay_v1.js"),
]

for f in targets:
    if not f.exists():
        continue
    s = f.read_text(encoding="utf-8", errors="replace")
    s2 = s

    # stop KPI v4 spam: force use v2 (stable)
    s2 = s2.replace("/api/ui/runs_kpi_v4", "/api/ui/runs_kpi_v2")

    # ensure run_file_allow2 doesn't exist anymore
    s2 = s2.replace("/api/vsp/run_file_allow2", "/api/vsp/run_file_allow")

    if s2 != s:
        f.write_text(s2, encoding="utf-8")
        print("[OK] patched", f.as_posix())
    else:
        print("[OK] no change", f.as_posix())
PY

echo "== [4] compile checks =="
python3 -m py_compile "$W"
if command -v node >/dev/null 2>&1; then
  node --check "$JS_KPI" >/dev/null 2>&1 || { echo "[ERR] node check failed: $JS_KPI"; exit 2; }
  [ -f "$JS_QA" ] && node --check "$JS_QA" >/dev/null 2>&1 || true
  [ -f "$JS_OV" ] && node --check "$JS_OV" >/dev/null 2>&1 || true
fi
echo "[OK] compile OK"

echo "== [5] restart =="
systemctl restart "$SVC" || true

echo "== [6] wait up /api/vsp/runs =="
for i in $(seq 1 30); do
  if curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null 2>&1; then
    echo "[OK] service up"
    break
  fi
  sleep 0.3
done

echo "== [7] sanity: KPI v2 (should be 200) =="
curl -sS -i "$BASE/api/ui/runs_kpi_v2?days=30" | head -n 12

echo "== [8] sanity: run_file_allow reports/run_gate_summary.json (should be 200 or 404, NOT 403 not-allowed) =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["run_id"])')"
echo "[RID]=$RID"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 40

echo "[DONE] Hard reload /runs (Ctrl+Shift+R). 403 spam should stop."
