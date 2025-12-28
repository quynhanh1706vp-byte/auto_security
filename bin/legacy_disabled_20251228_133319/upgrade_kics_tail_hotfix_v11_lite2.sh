#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_before_kics_tail_v11lite2_${TS}"
echo "[BACKUP] $F.bak_before_kics_tail_v11lite2_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# find existing V11_LITE block
m = re.search(
    r"(?ms)^(?P<ind>[ \t]*)# === VSP_KICS_TAIL_HOTFIX_V11_LITE ===\s*$.*?"
    r"^(?P=ind)# === END VSP_KICS_TAIL_HOTFIX_V11_LITE ===\s*$\n?",
    t
)
if not m:
    raise SystemExit("[ERR] cannot find V11_LITE markers to upgrade")

ind = m.group("ind")

# detect indent unit from inside block (line starting with ind + unit + "import")
blk = t[m.start():m.end()]
mm = re.search(r"(?m)^(?P<i1>[ \t]+)import\b", blk)
unit = "    "
if mm and mm.group("i1").startswith(ind):
    cand = mm.group("i1")[len(ind):]
    if cand:
        unit = cand

I0 = ind
I1 = ind + unit
I2 = I1 + unit
I3 = I2 + unit
I4 = I3 + unit

new = []
new.append(f"{I0}# === VSP_KICS_TAIL_HOTFIX_V11_LITE2 ===\n")
new.append(f"{I0}try:\n")
new.append(f"{I1}import os, json\n")
new.append(f"{I1}from pathlib import Path\n")
new.append(f"{I1}NL = chr(10)\n")
new.append(f"{I1}# ensure _out exists\n")
new.append(f"{I1}if '_out' not in locals():\n")
new.append(f"{I2}_out = _vsp_contractize(_VSP_FALLBACK_REQ[req_id])\n")
new.append(f"{I1}_stage = str(_out.get('stage_name') or '').lower()\n")
new.append(f"{I1}_ci = str(_out.get('ci_run_dir') or _out.get('ci_dir') or '')\n")

# statefile candidates (same as before, but robust)
new.append(f"{I1}if not _ci:\n")
new.append(f"{I2}base = Path(__file__).resolve().parent\n")
new.append(f"{I2}cands = [\n")
new.append(f"{I3}base / 'out_ci' / 'uireq_v1' / (req_id + '.json'),\n")
new.append(f"{I3}base / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),\n")
new.append(f"{I3}base / 'ui' / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),\n")
new.append(f"{I3}Path('/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1') / (req_id + '.json'),\n")
new.append(f"{I3}Path('/home/test/Data/SECURITY_BUNDLE/ui/ui/out_ci/uireq_v1') / (req_id + '.json'),\n")
new.append(f"{I2}]\n")
new.append(f"{I2}for st in cands:\n")
new.append(f"{I3}try:\n")
new.append(f"{I4}if st.exists():\n")
new.append(f"{I4}{unit}txt = st.read_text(encoding='utf-8', errors='ignore') or ''\n")
new.append(f"{I4}{unit}j = json.loads(txt) if txt.strip() else dict()\n")
new.append(f"{I4}{unit}_ci = str(j.get('ci_run_dir') or j.get('ci_dir') or '')\n")
new.append(f"{I4}{unit}if _ci:\n")
new.append(f"{I4}{unit}{unit}_out['ci_run_dir'] = _ci\n")
new.append(f"{I4}{unit}{unit}break\n")
new.append(f"{I3}except Exception:\n")
new.append(f"{I4}pass\n")

# choose kics log candidate
new.append(f"{I1}_klog = ''\n")
new.append(f"{I1}if _ci:\n")
new.append(f"{I2}_klog = os.path.join(_ci, 'kics', 'kics.log')\n")
new.append(f"{I2}if not os.path.exists(_klog):\n")
new.append(f"{I3}try:\n")
new.append(f"{I4}kd = Path(_ci) / 'kics'\n")
new.append(f"{I4}if kd.exists():\n")
new.append(f"{I4}{unit}logs = [x for x in kd.glob('*.log') if x.is_file()]\n")
new.append(f"{I4}{unit}logs.sort(key=lambda x: x.stat().st_mtime, reverse=True)\n")
new.append(f"{I4}{unit}if logs:\n")
new.append(f"{I4}{unit}{unit}_klog = str(logs[0])\n")
new.append(f"{I3}except Exception:\n")
new.append(f"{I4}pass\n")

# build tail
new.append(f"{I1}_tail_msg = ''\n")
new.append(f"{I1}if _klog and os.path.exists(_klog):\n")
new.append(f"{I2}rawb = Path(_klog).read_bytes()\n")
new.append(f"{I2}if len(rawb) > 65536:\n")
new.append(f"{I3}rawb = rawb[-65536:]\n")
new.append(f"{I2}raw = rawb.decode('utf-8', errors='ignore').replace(chr(13), NL)\n")
new.append(f"{I2}hb = ''\n")
new.append(f"{I2}for ln in reversed(raw.splitlines()):\n")
new.append(f"{I3}if '][HB]' in ln and '[KICS_V' in ln:\n")
new.append(f"{I3}{unit}hb = ln.strip(); break\n")
new.append(f"{I2}clean = [x for x in raw.splitlines() if x.strip()]\n")
new.append(f"{I2}ktail = NL.join(clean[-25:])\n")
new.append(f"{I2}if hb and (hb not in ktail):\n")
new.append(f"{I3}ktail = hb + NL + ktail\n")
new.append(f"{I2}_tail_msg = (ktail or '')[-4096:]\n")
new.append(f"{I1}else:\n")
new.append(f"{I2}# fallback: runner.log\n")
new.append(f"{I2}if _ci:\n")
new.append(f"{I3}rlog = os.path.join(_ci, 'runner.log')\n")
new.append(f"{I3}if os.path.exists(rlog):\n")
new.append(f"{I4}rawb = Path(rlog).read_bytes()\n")
new.append(f"{I4}if len(rawb) > 65536:\n")
new.append(f"{I4}{unit}rawb = rawb[-65536:]\n")
new.append(f"{I4}raw = rawb.decode('utf-8', errors='ignore').replace(chr(13), NL)\n")
new.append(f"{I4}clean = [x for x in raw.splitlines() if x.strip()]\n")
new.append(f"{I4}_tail_msg = ('[KICS_TAIL][fallback runner.log]' + NL + NL.join(clean[-25:]))[-4096:]\n")
new.append(f"{I2}if not _tail_msg:\n")
new.append(f"{I3}_tail_msg = '[KICS_TAIL] no kics log yet'\n")

new.append(f"{I1}_out['kics_tail'] = _tail_msg\n")
new.append(f"{I1}if 'kics' in _stage:\n")
new.append(f"{I2}_out['tail'] = _tail_msg\n")
new.append(f"{I0}except Exception:\n")
new.append(f"{I1}pass\n")
new.append(f"{I0}# === END VSP_KICS_TAIL_HOTFIX_V11_LITE2 ===\n")

t2 = t[:m.start()] + "".join(new) + t[m.end():]
p.write_text(t2, encoding="utf-8")
print("[OK] upgraded V11_LITE -> V11_LITE2 using unit=", repr(unit))
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== restart 8910 =="
PIDS="$(lsof -ti :8910 2>/dev/null || true)"
if [ -n "${PIDS}" ]; then
  echo "[KILL] 8910 pids: ${PIDS}"
  kill -9 ${PIDS} || true
fi
nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo
echo "[OK] done"
