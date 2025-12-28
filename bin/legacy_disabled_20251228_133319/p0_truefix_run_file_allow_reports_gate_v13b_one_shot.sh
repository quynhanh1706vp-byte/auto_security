#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need ls

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [0] snapshot current =="
cp -f "$W" "${W}.bak_v13b_snapshot_${TS}"
echo "[BACKUP] ${W}.bak_v13b_snapshot_${TS}"

echo "== [1] restore latest compiling candidate (current or backup) =="
python3 - <<'PY'
from pathlib import Path
import py_compile, os

w = Path("wsgi_vsp_ui_gateway.py")
cands = [w] + sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

good = None
for p in cands:
    try:
        py_compile.compile(str(p), doraise=True)
        good = p
        break
    except Exception:
        continue

if not good:
    raise SystemExit("[ERR] cannot find any compiling candidate (wsgi or backups)")

if good != w:
    w.write_text(good.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print(f"[OK] compiling candidate = {good.name}")
PY

echo "== [2] patch vsp_run_file_allow_v5 with correct indent (inside try) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
lines = s.splitlines(True)

# locate def
def_i = None
for i,l in enumerate(lines):
    if re.match(r'^[ \t]*def\s+vsp_run_file_allow_v5\s*\(\s*\)\s*:\s*$', l):
        def_i = i; break
if def_i is None:
    raise SystemExit("[ERR] cannot find def vsp_run_file_allow_v5()")

ind_def = re.match(r'^([ \t]*)', lines[def_i]).group(1)

# end of function: next def/@ at same indent
end_i = len(lines)
for j in range(def_i+1, len(lines)):
    if re.match(r'^[ \t]*$', lines[j]): 
        continue
    ind_j = re.match(r'^([ \t]*)', lines[j]).group(1)
    if len(ind_j) == len(ind_def) and re.match(r'^[ \t]*(def|@)\b', lines[j]):
        end_i = j
        break

func = lines[def_i:end_i]

# remove any previous broken V13 block (any indent)
out = []
skip = False
for l in func:
    if "VSP_P0_RUN_FILE_ALLOW_REPORTS_GATE_V13" in l and "---" in l:
        skip = True
        continue
    if skip:
        if "/VSP_P0_RUN_FILE_ALLOW_REPORTS_GATE_V13" in l:
            skip = False
        continue
    out.append(l)
func = out

func_text = "".join(func)

# find first rel assignment and its indent (THIS is the correct indent to stay inside try)
rel_idx = None
rel_ind = None
for idx,l in enumerate(func):
    m = re.match(r'^([ \t]*)rel\s*=\s*', l)
    if m:
        rel_idx = idx
        rel_ind = m.group(1)
        break
if rel_idx is None:
    raise SystemExit("[ERR] cannot find `rel = ...` inside vsp_run_file_allow_v5")

normalize_block = (
    f"{rel_ind}# --- VSP_P0_RUN_FILE_ALLOW_REPORTS_GATE_V13B ---\n"
    f"{rel_ind}# allow-key normalization for gate files; keep `rel` for file open\n"
    f"{rel_ind}rel_key = rel\n"
    f"{rel_ind}if isinstance(rel_key, str):\n"
    f"{rel_ind}    if rel_key.startswith('/'):\n"
    f"{rel_ind}        rel_key = rel_key[1:]\n"
    f"{rel_ind}    if rel_key.startswith('reports/'):\n"
    f"{rel_ind}        _tail = rel_key[len('reports/'):]\n"
    f"{rel_ind}        if _tail in ('run_gate_summary.json','run_gate.json'):\n"
    f"{rel_ind}            rel_key = _tail\n"
    f"{rel_ind}# --- /VSP_P0_RUN_FILE_ALLOW_REPORTS_GATE_V13B ---\n"
)

func.insert(rel_idx+1, normalize_block)
func_text2 = "".join(func)

has_extra = "__vsp_extra_allow" in func_text2

def repl_if(m):
    ind = m.group(1)
    if has_extra:
        return f"{ind}if (rel_key not in ALLOW) and (rel_key not in __vsp_extra_allow):\n"
    return f"{ind}if (rel_key not in ALLOW):\n"

# rewrite any "if ... not in ALLOW:" line inside this function
func_text2, n_if = re.subn(r'^([ \t]*)if[^\n]*not\s+in\s+ALLOW[^\n]*:\s*$',
                           repl_if, func_text2, flags=re.M)

# ALLOW.get(rel...) -> ALLOW.get(rel_key...)
func_text2, n_get = re.subn(r'\bALLOW\.get\(\s*rel(\s*[,\)])', r'ALLOW.get(rel_key\1', func_text2)
# ALLOW[rel] -> ALLOW[rel_key]
func_text2, n_idx = re.subn(r'\bALLOW\[\s*rel\s*\]', 'ALLOW[rel_key]', func_text2)

new = lines[:def_i] + func_text2.splitlines(True) + lines[end_i:]
p.write_text("".join(new), encoding="utf-8")
print(f"[OK] patched vsp_run_file_allow_v5: if_rewrite={n_if}, get_rewrite={n_get}, idx_rewrite={n_idx}")
PY

echo "== [3] compile check =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [4] restart =="
systemctl reset-failed "$SVC" 2>/dev/null || true
systemctl restart "$SVC" || true

echo "== [5] wait up (/api/vsp/runs) =="
ok=0
for _ in $(seq 1 60); do
  if curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null 2>&1; then ok=1; break; fi
  sleep 0.25
done
if [ "$ok" != "1" ]; then
  echo "[ERR] service not up; status/journal:"
  systemctl status "$SVC" --no-pager || true
  journalctl -u "$SVC" -n 120 --no-pager || true
  exit 3
fi
echo "[OK] service up"

echo "== [6] sanity: reports/run_gate_summary.json must NOT be 403-not-allowed =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["run_id"])')"
echo "[RID]=$RID"

curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 60
echo "----"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" | head -n 60

echo "[DONE] If it is 200 (or 404 file-not-found) and NOT 403-not-allowed => OK. Hard reload /runs."
