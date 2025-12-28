#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kics_tail_v11_${TS}"
echo "[BACKUP] $F.bak_kics_tail_v11_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

pat = re.compile(
    r"(?m)^(?P<ind>[ \t]*)# === VSP_STATUS_TAIL_OVERRIDE_KICS_V10_RETURNPATCH ===\s*\n"
    r".*?"
    r"^(?P=ind)# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V10_RETURNPATCH ===\s*\n"
    r"(?P=ind)return jsonify\(_out\), 200\s*\n?",
    flags=re.M | re.S
)
m = pat.search(t)
if not m:
    raise SystemExit("[ERR] cannot find V10 returnpatch block to upgrade")

ind = m.group("ind")
S = "    "  # internal indent, always prefixed with ind

block = []
block.append(f"{ind}# === VSP_STATUS_TAIL_OVERRIDE_KICS_V11_RETURNPATCH ===\n")
block.append(f"{ind}_out = _vsp_contractize(_VSP_FALLBACK_REQ[req_id])\n")
block.append(f"{ind}try:\n")
block.append(f"{ind}{S}import os, json\n")
block.append(f"{ind}{S}from pathlib import Path\n")
block.append(f"{ind}{S}NL = chr(10)\n")
block.append(f"{ind}{S}_stage = str(_out.get('stage_name') or '').lower()\n")
block.append(f"{ind}{S}_ci = str(_out.get('ci_run_dir') or _out.get('ci_dir') or '')\n")
block.append(f"{ind}{S}base = Path(__file__).resolve().parent\n")
block.append(f"{ind}{S}cands = [\n")
block.append(f"{ind}{S}{S}base / 'out_ci' / 'uireq_v1' / (req_id + '.json'),\n")
block.append(f"{ind}{S}{S}base / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),\n")
block.append(f"{ind}{S}{S}base / 'ui' / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),\n")
block.append(f"{ind}{S}{S}Path('/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1') / (req_id + '.json'),\n")
block.append(f"{ind}{S}{S}Path('/home/test/Data/SECURITY_BUNDLE/ui/ui/out_ci/uireq_v1') / (req_id + '.json'),\n")
block.append(f"{ind}{S}]\n")
block.append(f"{ind}{S}if not _ci:\n")
block.append(f"{ind}{S}{S}for _st in cands:\n")
block.append(f"{ind}{S}{S}{S}try:\n")
block.append(f"{ind}{S}{S}{S}{S}if _st.exists():\n")
block.append(f"{ind}{S}{S}{S}{S}{S}txt = _st.read_text(encoding='utf-8', errors='ignore') or ''\n")
block.append(f"{ind}{S}{S}{S}{S}{S}j = json.loads(txt) if txt.strip() else dict()\n")
block.append(f"{ind}{S}{S}{S}{S}{S}_ci = str(j.get('ci_run_dir') or j.get('ci_dir') or '')\n")
block.append(f"{ind}{S}{S}{S}{S}{S}if _ci:\n")
block.append(f"{ind}{S}{S}{S}{S}{S}{S}_out['ci_run_dir'] = _ci\n")
block.append(f"{ind}{S}{S}{S}{S}{S}{S}break\n")
block.append(f"{ind}{S}{S}{S}except Exception:\n")
block.append(f"{ind}{S}{S}{S}{S}pass\n")
block.append(f"{ind}{S}if _ci:\n")
block.append(f"{ind}{S}{S}_klog = os.path.join(_ci, 'kics', 'kics.log')\n")
block.append(f"{ind}{S}{S}if os.path.exists(_klog):\n")
block.append(f"{ind}{S}{S}{S}rawb = Path(_klog).read_bytes()\n")
block.append(f"{ind}{S}{S}{S}if len(rawb) > 65536:\n")
block.append(f"{ind}{S}{S}{S}{S}rawb = rawb[-65536:]\n")
block.append(f"{ind}{S}{S}{S}raw = rawb.decode('utf-8', errors='ignore').replace(chr(13), NL)\n")
block.append(f"{ind}{S}{S}{S}hb = ''\n")
block.append(f"{ind}{S}{S}{S}for ln in reversed(raw.splitlines()):\n")
block.append(f"{ind}{S}{S}{S}{S}if '][HB]' in ln and '[KICS_V' in ln:\n")
block.append(f"{ind}{S}{S}{S}{S}{S}hb = ln.strip()\n")
block.append(f"{ind}{S}{S}{S}{S}{S}break\n")
block.append(f"{ind}{S}{S}{S}clean = [x for x in raw.splitlines() if x.strip()]\n")
block.append(f"{ind}{S}{S}{S}ktail = NL.join(clean[-25:])\n")
block.append(f"{ind}{S}{S}{S}if hb and (hb not in ktail):\n")
block.append(f"{ind}{S}{S}{S}{S}ktail = hb + NL + ktail\n")
block.append(f"{ind}{S}{S}{S}_out['kics_tail'] = (ktail or '')[-4096:]\n")
block.append(f"{ind}{S}{S}{S}if 'kics' in _stage:\n")
block.append(f"{ind}{S}{S}{S}{S}_out['tail'] = _out.get('kics_tail','')\n")
block.append(f"{ind}except Exception:\n")
block.append(f"{ind}{S}pass\n")
block.append(f"{ind}# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V11_RETURNPATCH ===\n")
block.append(f"{ind}return jsonify(_out), 200\n")

t2 = pat.sub(''.join(block), t, count=1)
p.write_text(t2, encoding="utf-8")
print("[OK] upgraded V10 -> V11 (statefile candidate paths)")
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
