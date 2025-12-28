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

cp -f "$W" "${W}.bak_truefix_v14_${TS}"
echo "[BACKUP] ${W}.bak_truefix_v14_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8",errors="replace")

m=re.search(r'add_url_rule\(\s*["\']/api/vsp/run_file_allow["\']\s*,\s*["\'][^"\']+["\']\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*,', s)
fn=m.group(1) if m else None
if not fn:
    raise SystemExit("[ERR] cannot detect function for /api/vsp/run_file_allow")

# locate function block
m2=re.search(r'(?m)^\s*def\s+'+re.escape(fn)+r'\s*\(', s)
if not m2:
    raise SystemExit(f"[ERR] cannot find def {fn}")
start=m2.start()

# function ends at next "def " at col 0 (best-effort)
m3=re.search(r'(?m)^\s*def\s+[A-Za-z_]\w*\s*\(', s[m2.end():])
end = start + m3.start() if m3 else len(s)
block=s[start:end]
lines=block.splitlines(True)

# find rel assignment line
rel_i=None
for i,ln in enumerate(lines):
    if "_safe_rel" in ln and "request.args.get" in ln and "path" in ln and re.search(r'^\s*rel\s*=\s*_safe_rel', ln):
        rel_i=i
        break
if rel_i is None:
    raise SystemExit("[ERR] cannot find `rel = _safe_rel(request.args.get(\"path\")...)` inside handler")

indent=re.match(r'^(\s*)', lines[rel_i]).group(1)

# find allow-check line after rel (the first if that checks ALLOW and returns not allowed)
allow_if_i=None
for i in range(rel_i+1, min(rel_i+120, len(lines))):
    if re.search(r'^\s*if\b', lines[i]) and ("ALLOW" in lines[i]) and ("not in" in lines[i]):
        # heuristic: check a few next lines include "not allowed"
        nxt="".join(lines[i:i+6])
        if "not allowed" in nxt:
            allow_if_i=i
            break
if allow_if_i is None:
    # fallback: find the return jsonify err not allowed, then take nearest preceding if
    ret_i=None
    for i in range(rel_i+1, min(rel_i+180, len(lines))):
        if "not allowed" in lines[i] and ("jsonify" in lines[i] or "return" in lines[i]):
            ret_i=i
            break
    if ret_i is None:
        raise SystemExit("[ERR] cannot locate allow-check/return not-allowed region")
    for j in range(ret_i, rel_i, -1):
        if re.search(r'^\s*if\b', lines[j]):
            allow_if_i=j
            break
    if allow_if_i is None:
        raise SystemExit("[ERR] cannot backtrack to allow-check if-line")

# Now rewrite a clean block:
# - keep original rel assignment line
# - insert our V14 gate allow logic
# - keep the original allow-check IF line but rewrite it to use rel/rel_key robustly, and keep return line(s) unchanged
orig_rel_line = lines[rel_i]

# rewrite allow-if line: force a robust condition (do NOT depend on old rel_key bugs)
# We'll keep the original return block lines as-is, only replace the IF condition line.
new_if = (
    f"{indent}if (rel_key not in ALLOW) and (rel not in ALLOW) and "
    f"(rel_key not in __vsp_extra_allow) and (rel not in __vsp_extra_allow):\n"
)

# build injected snippet
inj = []
inj.append(f"{indent}# --- VSP_P0_RUN_FILE_ALLOW_REPORTS_GATE_V14 ---\n")
inj.append(f"{indent}rel = (rel or '').strip().lstrip('/')\n")
inj.append(f"{indent}rel_key = rel\n")
inj.append(f"{indent}if isinstance(rel, str) and rel.startswith('reports/'):\n")
inj.append(f"{indent}    _tail = rel.split('/',1)[1]\n")
inj.append(f"{indent}    if _tail in ('run_gate_summary.json','run_gate.json'):\n")
inj.append(f"{indent}        rel_key = _tail\n")
inj.append(f"{indent}try:\n")
inj.append(f"{indent}    # allow reports/ gate files explicitly (for file open path)\n")
inj.append(f"{indent}    ALLOW.update({{'reports/run_gate_summary.json','reports/run_gate.json'}})\n")
inj.append(f"{indent}except Exception:\n")
inj.append(f"{indent}    pass\n")
inj.append(f"{indent}__vsp_extra_allow = set(['reports/run_gate_summary.json','reports/run_gate.json','run_gate_summary.json','run_gate.json'])\n")
inj.append(f"{indent}# --- /VSP_P0_RUN_FILE_ALLOW_REPORTS_GATE_V14 ---\n")

# replace region: from rel_i+1 up to allow_if_i (exclusive) with inj
# and replace allow_if line with new_if
new_lines=[]
for i,ln in enumerate(lines):
    if i == rel_i:
        new_lines.append(orig_rel_line)
        continue
    if i == rel_i+1:
        # skip everything until allow_if_i
        new_lines.extend(inj)
        # jump to allow_if_i
        continue
    if rel_i+1 < i < allow_if_i:
        continue
    if i == allow_if_i:
        new_lines.append(new_if)
        continue
    # normal keep
    if i <= rel_i:
        new_lines.append(ln)
    elif i > allow_if_i:
        new_lines.append(ln)

new_block="".join(new_lines)
s2 = s[:start] + new_block + s[end:]
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched {fn}: injected V14 block and normalized allow-check")
PY

echo "== py_compile =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== wait /api/vsp/runs =="
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null 2>&1; then
    echo "[OK] up"
    break
  fi
  sleep 0.6
done

echo "== sanity: reports/run_gate_summary.json should NOT be 403 not-allowed =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["run_id"])')"
echo "[RID]=$RID"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 40

echo
echo "[DONE] If status is 200 and body is JSON (or 404 file missing), you're good. Hard reload /runs."
