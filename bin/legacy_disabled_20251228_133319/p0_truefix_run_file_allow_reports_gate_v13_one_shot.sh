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

echo "== [1] snapshot =="
cp -f "$W" "${W}.bak_runfileallow_v13_${TS}"
echo "[BACKUP] ${W}.bak_runfileallow_v13_${TS}"

echo "== [2] patch vsp_run_file_allow_v5 (reports/ gate normalize + fix allow-check) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
if "VSP_P0_RUN_FILE_ALLOW_REPORTS_GATE_V13" in s:
    print("[OK] marker already present (skip)")
    raise SystemExit(0)

# find def vsp_run_file_allow_v5
m = re.search(r'^(?P<ind>[ \t]*)def\s+vsp_run_file_allow_v5\s*\(\s*\)\s*:\s*$', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def vsp_run_file_allow_v5()")
ind_def = m.group("ind")
lines = s.splitlines(True)

# locate def line index
def_i = None
for i, line in enumerate(lines):
    if re.match(r'^[ \t]*def\s+vsp_run_file_allow_v5\s*\(\s*\)\s*:\s*$', line):
        def_i = i; break
if def_i is None:
    raise SystemExit("[ERR] cannot locate def index")

# find end index: next top-level at same indent starting with def/@, or EOF
end_i = len(lines)
for j in range(def_i+1, len(lines)):
    if re.match(r'^[ \t]*$', lines[j]):  # blank ok
        continue
    # indentation length
    ind_j = re.match(r'^([ \t]*)', lines[j]).group(1)
    if len(ind_j) == len(ind_def) and re.match(r'^[ \t]*(def|@)\b', lines[j]):
        end_i = j
        break

func = lines[def_i:end_i]
func_text = "".join(func)

# detect body indent (def indent + 4 spaces) robustly: find first non-blank after def
body_ind = ind_def + "    "
for k in range(def_i+1, end_i):
    if lines[k].strip():
        body_ind = re.match(r'^([ \t]*)', lines[k]).group(1)
        break

# insert normalize block right AFTER first "rel =" assignment
rel_assign_idx = None
for idx, line in enumerate(func):
    if re.match(r'^[ \t]*rel\s*=\s*', line):
        rel_assign_idx = idx
        break
if rel_assign_idx is None:
    raise SystemExit("[ERR] cannot find `rel = ...` inside vsp_run_file_allow_v5")

normalize_block = (
    f"{body_ind}# --- VSP_P0_RUN_FILE_ALLOW_REPORTS_GATE_V13 ---\n"
    f"{body_ind}# normalize allow-key for gate files only; keep `rel` for file-open\n"
    f"{body_ind}rel_key = rel\n"
    f"{body_ind}if isinstance(rel_key, str):\n"
    f"{body_ind}    if rel_key.startswith('/'):\n"
    f"{body_ind}        rel_key = rel_key[1:]\n"
    f"{body_ind}    if rel_key.startswith('reports/'):\n"
    f"{body_ind}        _tail = rel_key[len('reports/'):]\n"
    f"{body_ind}        if _tail in ('run_gate_summary.json','run_gate.json'):\n"
    f"{body_ind}            rel_key = _tail\n"
    f"{body_ind}# --- /VSP_P0_RUN_FILE_ALLOW_REPORTS_GATE_V13 ---\n"
)

func.insert(rel_assign_idx+1, normalize_block)
func_text2 = "".join(func)

# Fix broken allow-check logic: replace ANY line with "not in ALLOW" in this function to use rel_key
# Prefer preserving optional __vsp_extra_allow if present.
has_extra = "__vsp_extra_allow" in func_text2

def repl_if_line(match):
    ind = match.group(1)
    if has_extra:
        return f"{ind}if (rel_key not in ALLOW) and (rel_key not in __vsp_extra_allow):\n"
    return f"{ind}if (rel_key not in ALLOW):\n"

func_text2, n_if = re.subn(
    r'^([ \t]*)if[^\n]*not\s+in\s+ALLOW[^\n]*:\s*$',
    repl_if_line,
    func_text2,
    flags=re.M
)

# Fix ALLOW.get(rel...) usages inside function to ALLOW.get(rel_key...)
func_text2, n_get = re.subn(r'\bALLOW\.get\(\s*rel(\s*[,\)])', r'ALLOW.get(rel_key\1', func_text2)

# Also fix ALLOW[rel] -> ALLOW[rel_key] (rare but safe)
func_text2, n_idx = re.subn(r'\bALLOW\[\s*rel\s*\]', 'ALLOW[rel_key]', func_text2)

# Put back
new_lines = lines[:def_i] + func_text2.splitlines(True) + lines[end_i:]
p.write_text("".join(new_lines), encoding="utf-8")
print(f"[OK] patched vsp_run_file_allow_v5: if_lines_rewritten={n_if}, ALLOW.get_rewritten={n_get}, ALLOW[idx]_rewritten={n_idx}")
PY

echo "== [3] compile check =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [4] restart =="
systemctl reset-failed "$SVC" 2>/dev/null || true
systemctl restart "$SVC" || true

echo "== [5] wait up (/api/vsp/runs) =="
ok=0
for _ in $(seq 1 40); do
  if curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null 2>&1; then ok=1; break; fi
  sleep 0.25
done
if [ "$ok" != "1" ]; then
  echo "[ERR] service not up; last journal:"
  journalctl -u "$SVC" -n 80 --no-pager || true
  exit 3
fi
echo "[OK] service up"

echo "== [6] sanity: run_file_allow reports/run_gate_summary.json should NOT be 403-not-allowed =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["run_id"])')"
echo "[RID]=$RID"

curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 60
echo "----"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" | head -n 60

echo "[DONE] If status is 200 (or 404 file-not-found) and NOT 403-not-allowed => OK. Hard reload /runs (Ctrl+Shift+R)."
