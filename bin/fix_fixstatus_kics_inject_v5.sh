#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "== [A] restore from latest bak_fixstatus_kics_v4_* =="
BAK="$(ls -1t vsp_demo_app.py.bak_fixstatus_kics_v4_* 2>/dev/null | head -n 1 || true)"
[ -n "$BAK" ] || { echo "[ERR] no backup vsp_demo_app.py.bak_fixstatus_kics_v4_* found"; exit 2; }
cp -f "$BAK" "$F"
echo "[OK] restored: $BAK -> $F"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fixstatus_kics_v5_${TS}"
echo "[BACKUP] $F.bak_fixstatus_kics_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_FIX_STATUS_V16_INJECT_KICS_SUMMARY_V5 ==="
if TAG in t:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# find latest guess fn
guess_names = re.findall(r'(?m)^\s*def\s+(_vsp_guess_ci_run_dir_from_rid_v\d+)\s*\(', t)
guess_fn = guess_names[-1] if guess_names else None
if not guess_fn:
    print("[ERR] cannot find _vsp_guess_ci_run_dir_from_rid_v*")
    raise SystemExit(2)
print("[OK] guess_fn =", guess_fn)

# locate function _vsp_fix_status_from_body_v16
m = re.search(r'(?m)^def\s+_vsp_fix_status_from_body_v16\s*\(\s*resp\s*\)\s*:', t)
if not m:
    print("[ERR] cannot find def _vsp_fix_status_from_body_v16(resp):")
    raise SystemExit(3)

lines = t.splitlines(True)

# map char index -> line index
cum = 0
start_i = None
for i, line in enumerate(lines):
    if cum <= m.start() < cum + len(line):
        start_i = i
        break
    cum += len(line)
if start_i is None:
    print("[ERR] mapping failed")
    raise SystemExit(4)

base_indent = re.match(r'^(\s*)', lines[start_i]).group(1)
base_col = len(base_indent)

end_i = len(lines)
for j in range(start_i + 1, len(lines)):
    s = lines[j]
    if s.strip() == "":
        continue
    ind = len(s) - len(s.lstrip(" "))
    if ind <= base_col and (s.lstrip().startswith("def ") or s.lstrip().startswith("@")):
        end_i = j
        break

fn_lines = lines[start_i:end_i]

# find the FIRST line that assigns payload/obj via json.loads(
load_idx = None
var = None
ind = None
for k, ln in enumerate(fn_lines):
    mm = re.search(r'^(?P<ind>\s*)(?P<var>payload|obj)\s*=\s*.*(?:_json|json)\.loads\(', ln)
    if mm:
        load_idx = k
        var = mm.group("var")
        ind = mm.group("ind")
        break

if load_idx is None:
    print("[ERR] cannot find payload/obj json.loads(...) assignment line in _vsp_fix_status_from_body_v16")
    raise SystemExit(5)

print("[OK] found loads line var=", var, "at local_line=", load_idx)

ind2 = ind + "    "

inject = []
inject.append(ind + TAG + "\n")
inject.append(ind + "try:\n")
inject.append(ind2 + "from flask import request as _req\n")
inject.append(ind2 + "_path = getattr(_req, 'path', '') or ''\n")
inject.append(ind2 + "# defaults (avoid UI crash)\n")
inject.append(ind2 + f"if isinstance({var}, dict):\n")
inject.append(ind2 + f"    {var}.setdefault('kics_verdict','')\n")
inject.append(ind2 + f"    {var}.setdefault('kics_total',0)\n")
inject.append(ind2 + f"    {var}.setdefault('kics_counts',{{}})\n")
inject.append(ind2 + "if _path.startswith('/api/vsp/run_status_v2/'):\n")
inject.append(ind2 + "    _rid = _path.rsplit('/', 1)[-1]\n")
inject.append(ind2 + f"    _ci = ({var}.get('ci_run_dir') if isinstance({var}, dict) else None) or {guess_fn}(_rid)\n")
inject.append(ind2 + "    if _ci and isinstance(_ci, str) and _ci.strip():\n")
inject.append(ind2 + f"        if isinstance({var}, dict):\n")
inject.append(ind2 + f"            {var}['ci_run_dir'] = _ci\n")
inject.append(ind2 + "        try:\n")
inject.append(ind2 + "            import json as __json\n")
inject.append(ind2 + "            from pathlib import Path as __P\n")
inject.append(ind2 + "            _fp = __P(_ci) / 'kics' / 'kics_summary.json'\n")
inject.append(ind2 + "            if _fp.exists():\n")
inject.append(ind2 + "                _raw = _fp.read_text(encoding='utf-8', errors='ignore') or ''\n")
inject.append(ind2 + "                _ks = __json.loads(_raw) if _raw.lstrip().startswith('{') else None\n")
inject.append(ind2 + f"                if isinstance(_ks, dict) and isinstance({var}, dict):\n")
inject.append(ind2 + f"                    {var}['kics_verdict'] = (_ks.get('verdict') or '')\n")
inject.append(ind2 + f"                    {var}['kics_total']   = int(_ks.get('total', 0) or 0)\n")
inject.append(ind2 + "                    _c = _ks.get('counts')\n")
inject.append(ind2 + f"                    {var}['kics_counts']  = (_c if isinstance(_c, dict) else {{}})\n")
inject.append(ind2 + "        except Exception:\n")
inject.append(ind2 + "            pass\n")
inject.append(ind + "except Exception:\n")
inject.append(ind2 + "pass\n")
inject.append(ind + "# === END VSP_FIX_STATUS_V16_INJECT_KICS_SUMMARY_V5 ===\n")

# INSERT AFTER THE WHOLE LINE (safe): after fn_lines[load_idx]
fn_lines2 = fn_lines[:load_idx+1] + inject + fn_lines[load_idx+1:]

# write back
out_lines = lines[:start_i] + fn_lines2 + lines[end_i:]
p.write_text("".join(out_lines), encoding="utf-8")
print("[OK] injected safely after loads line (line-boundary)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
