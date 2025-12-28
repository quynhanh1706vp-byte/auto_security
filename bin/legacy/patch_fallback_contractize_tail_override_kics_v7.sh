#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_tail_override_kics_v7_${TS}"
echo "[BACKUP] $F.bak_tail_override_kics_v7_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# locate def _fallback_run_status_v1(req_id):
def_i = None
def_ind = ""
for i,s in enumerate(lines):
    m = re.match(r"^([ \t]*)def\s+_fallback_run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", s)
    if m:
        def_i = i
        def_ind = m.group(1)
        break
if def_i is None:
    raise SystemExit("[ERR] cannot find def _fallback_run_status_v1(req_id)")

def_ind_len = len(def_ind)

# infer body indent
body_ind = None
for j in range(def_i+1, min(len(lines), def_i+4000)):
    if lines[j].strip() == "":
        continue
    ind = re.match(r"^([ \t]*)", lines[j]).group(1)
    if len(ind) > def_ind_len:
        body_ind = ind
        break
if body_ind is None:
    body_ind = def_ind + "    "

STEP = "\t" if ("\t" in body_ind and body_ind.replace("\t","") == "") else "    "

# find end of function by dedent
end_i = len(lines)
for j in range(def_i+1, len(lines)):
    if lines[j].strip() == "":
        continue
    ind = re.match(r"^([ \t]*)", lines[j]).group(1)
    if len(ind) <= def_ind_len:
        end_i = j
        break

func = lines[def_i:end_i]

# remove any previous injected tail blocks within this function (V5/V6/V6_FIXED_SAFE/V7 older)
def strip_marker_block(func_lines, marker_prefix):
    out=[]
    k=0
    while k < len(func_lines):
        if marker_prefix in func_lines[k]:
            k += 1
            while k < len(func_lines) and ("# === END " not in func_lines[k]):
                k += 1
            if k < len(func_lines):
                k += 1
            continue
        out.append(func_lines[k])
        k += 1
    return out

for pref in [
    "VSP_STATUS_TAIL_APPEND_KICS_HB_",
    "VSP_STATUS_TAIL_PREFER_KICS_LOG_",
    "VSP_STATUS_TAIL_OVERRIDE_KICS_V7",
]:
    func = strip_marker_block(func, pref)

# find the return line that does jsonify(_vsp_contractize(...)) in this function
ret_k = None
for k,s in enumerate(func):
    if re.search(r"return\s+jsonify\(\s*_vsp_contractize\(", s):
        ret_k = k
        break
if ret_k is None:
    raise SystemExit("[ERR] cannot find: return jsonify(_vsp_contractize(...)) inside _fallback_run_status_v1")

# replace that single-line return with multi-line: _out=contractize; override tail; return jsonify(_out)
TAG = "# === VSP_STATUS_TAIL_OVERRIDE_KICS_V7 ==="
END = "# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V7 ==="

new = []
new.append(f"{body_ind}_out = _vsp_contractize(_VSP_FALLBACK_REQ[req_id])\n")
new.append(f"{body_ind}{TAG}\n")
new.append(f"{body_ind}try:\n")
new.append(f"{body_ind}{STEP}import os\n")
new.append(f"{body_ind}{STEP}_stage = str(_out.get('stage_name') or '').lower()\n")
new.append(f"{body_ind}{STEP}_ci = str(_out.get('ci_run_dir') or '')\n")
new.append(f"{body_ind}{STEP}if ('kics' in _stage) and _ci:\n")
new.append(f"{body_ind}{STEP}{STEP}_klog = os.path.join(_ci, 'kics', 'kics.log')\n")
new.append(f"{body_ind}{STEP}{STEP}if os.path.exists(_klog):\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}with open(_klog, 'rb') as fh:\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}{STEP}rawb = fh.read()\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}if len(rawb) > 65536:\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}{STEP}rawb = rawb[-65536:]\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}raw = rawb.decode('utf-8', errors='ignore').replace('\\\\r','\\\\n')\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}hb = ''\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}for ln in reversed(raw.splitlines()):\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}{STEP}if '][HB]' in ln and '[KICS_V' in ln:\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}{STEP}{STEP}hb = ln.strip()\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}{STEP}{STEP}break\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}clean = [x for x in raw.splitlines() if x.strip()]\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}tail = '\\\\n'.join(clean[-25:])\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}if hb and (hb not in tail):\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}{STEP}tail = hb + '\\\\n' + tail\n")
new.append(f"{body_ind}{STEP}{STEP}{STEP}_out['tail'] = (tail or '')[-4096:]\n")
new.append(f"{body_ind}except Exception:\n")
new.append(f"{body_ind}{STEP}pass\n")
new.append(f"{body_ind}{END}\n")
new.append(f"{body_ind}return jsonify(_out), 200\n")

func2 = func[:ret_k] + new + func[ret_k+1:]
new_lines = lines[:def_i] + func2 + lines[end_i:]
p.write_text("".join(new_lines), encoding="utf-8")
print(f"[OK] replaced return@func_line={ret_k+1} with contractize+override+return")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

# restart 8910
PIDS="$(lsof -ti :8910 2>/dev/null || true)"
if [ -n "${PIDS}" ]; then
  echo "[KILL] 8910 pids: ${PIDS}"
  kill -9 ${PIDS} || true
fi
nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo
echo "[OK] patched + restarted"
