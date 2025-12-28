#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kics_tail_v8_${TS}"
echo "[BACKUP] $F.bak_kics_tail_v8_${TS}"

# ensure compilable (restore if needed)
if ! python3 -m py_compile "$F" >/dev/null 2>&1; then
  echo "[WARN] current file does NOT compile. restoring latest compilable backup..."
  CANDS="$(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true)"
  [ -n "$CANDS" ] || { echo "[ERR] no backups found"; exit 2; }
  OK=""
  for B in $CANDS; do
    cp -f "$B" "$F"
    if python3 -m py_compile "$F" >/dev/null 2>&1; then OK="$B"; break; fi
  done
  [ -n "$OK" ] || { echo "[ERR] no compilable backup found"; exit 3; }
  echo "[OK] restored $F <= $OK"
fi

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# find V7 block inside _fallback_run_status_v1 and replace with V8
mdef = re.search(r"(?m)^(?P<ind>[ \t]*)def\s+_fallback_run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", t)
if not mdef:
    raise SystemExit("[ERR] cannot find _fallback_run_status_v1")

def_ind = mdef.group("ind")
def_pos = mdef.start()

lines = t.splitlines(True)
pos = 0
def_i = None
for i,ln in enumerate(lines):
    if pos <= def_pos < pos + len(ln):
        def_i = i; break
    pos += len(ln)
if def_i is None:
    raise SystemExit("[ERR] cannot map def line")

def_ind_len = len(def_ind)
end_i = len(lines)
for j in range(def_i+1, len(lines)):
    if lines[j].strip()=="":
        continue
    ind = re.match(r"^([ \t]*)", lines[j]).group(1)
    if len(ind) <= def_ind_len:
        end_i = j
        break

func = lines[def_i:end_i]

# detect body indent step
body_ind = None
for j in range(1, min(len(func), 2000)):
    if func[j].strip()=="":
        continue
    ind = re.match(r"^([ \t]*)", func[j]).group(1)
    if len(ind) > def_ind_len:
        body_ind = ind
        break
if body_ind is None:
    body_ind = def_ind + "    "
STEP = "\t" if ("\t" in body_ind and body_ind.replace("\t","")=="" ) else "    "

# locate V7 marker block
tag = "VSP_STATUS_TAIL_OVERRIDE_KICS_V7"
b0 = b1 = None
for i,ln in enumerate(func):
    if tag in ln:
        b0 = i
        break
if b0 is None:
    raise SystemExit("[ERR] V7 block not found (cannot upgrade to V8)")

# find END
endtag = "# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V7 ==="
for j in range(b0+1, len(func)):
    if endtag in func[j]:
        b1 = j
        break
if b1 is None:
    raise SystemExit("[ERR] V7 END marker not found")

# indentation for insertion = indentation of TAG line
ret_ind = re.match(r"^([ \t]*)", func[b0]).group(1)

V8_TAG = "# === VSP_STATUS_TAIL_OVERRIDE_KICS_V8 ==="
V8_END = "# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V8 ==="

block = []
block.append(f"{ret_ind}{V8_TAG}\n")
block.append(f"{ret_ind}try:\n")
block.append(f"{ret_ind}{STEP}import os\n")
block.append(f"{ret_ind}{STEP}from pathlib import Path\n")
block.append(f"{ret_ind}{STEP}_stage = str(_out.get('stage_name') or '').lower()\n")
block.append(f"{ret_ind}{STEP}_ci = str(_out.get('ci_run_dir') or '')\n")
block.append(f"{ret_ind}{STEP}if _ci:\n")
block.append(f"{ret_ind}{STEP}{STEP}_klog = os.path.join(_ci, 'kics', 'kics.log')\n")
block.append(f"{ret_ind}{STEP}{STEP}if os.path.exists(_klog):\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}rawb = Path(_klog).read_bytes()\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}if len(rawb) > 65536:\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}{STEP}rawb = rawb[-65536:]\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}raw = rawb.decode('utf-8', errors='ignore').replace('\\\\r','\\\\n')\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}hb = ''\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}for ln in reversed(raw.splitlines()):\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}{STEP}if '][HB]' in ln and '[KICS_V' in ln:\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}{STEP}{STEP}hb = ln.strip(); break\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}clean = [x for x in raw.splitlines() if x.strip()]\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}ktail = '\\\\n'.join(clean[-25:])\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}if hb and (hb not in ktail):\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}{STEP}ktail = hb + '\\\\n' + ktail\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}_out['kics_tail'] = (ktail or '')[-4096:]\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}# only override main tail when stage is KICS\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}if 'kics' in _stage:\n")
block.append(f"{ret_ind}{STEP}{STEP}{STEP}{STEP}_out['tail'] = _out['kics_tail']\n")
block.append(f"{ret_ind}except Exception:\n")
block.append(f"{ret_ind}{STEP}pass\n")
block.append(f"{ret_ind}{V8_END}\n")

func2 = func[:b0] + block + func[b1+1:]
p.write_text("".join(lines[:def_i] + func2 + lines[end_i:]), encoding="utf-8")
print("[OK] upgraded V7 -> V8 (kics_tail field)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

PIDS="$(lsof -ti :8910 2>/dev/null || true)"
if [ -n "${PIDS}" ]; then
  echo "[KILL] 8910 pids: ${PIDS}"
  kill -9 ${PIDS} || true
fi
nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo
echo "[OK] done"
