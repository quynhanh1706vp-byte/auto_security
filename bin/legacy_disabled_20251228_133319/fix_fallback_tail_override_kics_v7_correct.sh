#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "== [1] backup current =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_tail_override_kics_v7_${TS}"
echo "[BACKUP] $F.bak_fix_tail_override_kics_v7_${TS}"

echo "== [2] ensure file compilable (auto-restore if needed) =="
if python3 -m py_compile "$F" >/dev/null 2>&1; then
  echo "[OK] current file compiles"
else
  echo "[WARN] current file does NOT compile. searching backups..."
  CANDS="$(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true)"
  [ -n "$CANDS" ] || { echo "[ERR] no backups found: vsp_demo_app.py.bak_*"; exit 2; }

  OK_BAK=""
  for B in $CANDS; do
    cp -f "$B" "$F"
    if python3 -m py_compile "$F" >/dev/null 2>&1; then
      OK_BAK="$B"
      break
    fi
  done
  [ -n "$OK_BAK" ] || { echo "[ERR] no compilable backup found"; exit 3; }
  echo "[OK] restored $F <= $OK_BAK"
fi

echo "== [3] patch ONLY final return of _fallback_run_status_v1 (contractize -> override tail from kics.log) =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# locate def _fallback_run_status_v1(req_id):
mdef = re.search(r"(?m)^(?P<ind>[ \t]*)def\s+_fallback_run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", t)
if not mdef:
    raise SystemExit("[ERR] cannot find def _fallback_run_status_v1(req_id)")

def_ind = mdef.group("ind")
def_pos = mdef.start()

# find function end by dedent (next line with indent <= def indent)
lines = t.splitlines(True)
# map char pos -> line index
pos = 0
def_i = None
for i,ln in enumerate(lines):
    if pos <= def_pos < pos + len(ln):
        def_i = i
        break
    pos += len(ln)
if def_i is None:
    raise SystemExit("[ERR] cannot map def line index")

def_ind_len = len(def_ind)

# infer body indent
body_ind = None
for j in range(def_i+1, min(len(lines), def_i+3000)):
    if lines[j].strip() == "":
        continue
    ind = re.match(r"^([ \t]*)", lines[j]).group(1)
    if len(ind) > def_ind_len:
        body_ind = ind
        break
if body_ind is None:
    body_ind = def_ind + "    "
STEP = "\t" if ("\t" in body_ind and body_ind.replace("\t","") == "") else "    "

# find end of function
end_i = len(lines)
for j in range(def_i+1, len(lines)):
    if lines[j].strip() == "":
        continue
    ind = re.match(r"^([ \t]*)", lines[j]).group(1)
    if len(ind) <= def_ind_len:
        end_i = j
        break

func = lines[def_i:end_i]

# remove any previous V7 marker blocks inside function (best-effort)
func2=[]
k=0
while k < len(func):
    if "VSP_STATUS_TAIL_OVERRIDE_KICS_V7" in func[k]:
        # skip until END marker
        k += 1
        while k < len(func) and ("# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V7 ===" not in func[k]):
            k += 1
        if k < len(func): k += 1
        continue
    func2.append(func[k]); k += 1
func = func2

# IMPORTANT: choose the *final success return* that contains _VSP_FALLBACK_REQ[req_id]
ret_idxs = []
for k,ln in enumerate(func):
    if re.search(r"return\s+jsonify\(\s*_vsp_contractize\(", ln) and ("_VSP_FALLBACK_REQ[req_id]" in ln):
        ret_idxs.append(k)

if not ret_idxs:
    # sometimes return spans multiple lines; fallback: find any line with '_VSP_FALLBACK_REQ[req_id]' and 'return jsonify'
    for k,ln in enumerate(func):
        if ("_VSP_FALLBACK_REQ[req_id]" in ln) and ("return" in ln) and ("jsonify" in ln):
            ret_idxs.append(k)

if not ret_idxs:
    raise SystemExit("[ERR] cannot find final return line containing _VSP_FALLBACK_REQ[req_id] in _fallback_run_status_v1")

ret_k = ret_idxs[-1]
ret_line = func[ret_k]
ret_ind = re.match(r"^([ \t]*)", ret_line).group(1)

TAG = "# === VSP_STATUS_TAIL_OVERRIDE_KICS_V7 ==="
END = "# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V7 ==="

new = []
new.append(f"{ret_ind}_out = _vsp_contractize(_VSP_FALLBACK_REQ[req_id])\n")
new.append(f"{ret_ind}{TAG}\n")
new.append(f"{ret_ind}try:\n")
new.append(f"{ret_ind}{STEP}import os\n")
new.append(f"{ret_ind}{STEP}_stage = str(_out.get('stage_name') or '').lower()\n")
new.append(f"{ret_ind}{STEP}_ci = str(_out.get('ci_run_dir') or '')\n")
new.append(f"{ret_ind}{STEP}if ('kics' in _stage) and _ci:\n")
new.append(f"{ret_ind}{STEP}{STEP}_klog = os.path.join(_ci, 'kics', 'kics.log')\n")
new.append(f"{ret_ind}{STEP}{STEP}if os.path.exists(_klog):\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}rawb = Path(_klog).read_bytes()\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}if len(rawb) > 65536:\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}{STEP}rawb = rawb[-65536:]\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}raw = rawb.decode('utf-8', errors='ignore').replace('\\\\r','\\\\n')\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}hb = ''\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}for ln in reversed(raw.splitlines()):\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}{STEP}if '][HB]' in ln and '[KICS_V' in ln:\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}{STEP}{STEP}hb = ln.strip(); break\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}clean = [x for x in raw.splitlines() if x.strip()]\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}tail = '\\\\n'.join(clean[-25:])\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}if hb and (hb not in tail):\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}{STEP}tail = hb + '\\\\n' + tail\n")
new.append(f"{ret_ind}{STEP}{STEP}{STEP}_out['tail'] = (tail or '')[-4096:]\n")
new.append(f"{ret_ind}except Exception:\n")
new.append(f"{ret_ind}{STEP}pass\n")
new.append(f"{ret_ind}{END}\n")
# keep same return signature ", 200" if present
if ", 200" in ret_line:
    new.append(f"{ret_ind}return jsonify(_out), 200\n")
else:
    new.append(f"{ret_ind}return jsonify(_out)\n")

func = func[:ret_k] + new + func[ret_k+1:]
new_text = "".join(lines[:def_i] + func + lines[end_i:])
p.write_text(new_text, encoding="utf-8")
print(f"[OK] patched final return in _fallback_run_status_v1 at func_line={ret_k+1}")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [4] restart 8910 =="
PIDS="$(lsof -ti :8910 2>/dev/null || true)"
if [ -n "${PIDS}" ]; then
  echo "[KILL] 8910 pids: ${PIDS}"
  kill -9 ${PIDS} || true
fi
nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo
echo "[OK] done"
