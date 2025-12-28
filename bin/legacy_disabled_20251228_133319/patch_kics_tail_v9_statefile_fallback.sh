#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kics_tail_v9_${TS}"
echo "[BACKUP] $F.bak_kics_tail_v9_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

pat = re.compile(
    r"(?m)^(?P<ind>[ \t]*)# === VSP_STATUS_TAIL_OVERRIDE_KICS_V8 ===\s*\n"
    r".*?"
    r"^(?P=ind)# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V8 ===\s*\n?",
    flags=re.M | re.S
)
m = pat.search(t)
if not m:
    raise SystemExit("[ERR] cannot find V8 block markers to upgrade")

ind = m.group("ind")
step = "    "  # file is 4-space indented in this section

block = (
f"{ind}# === VSP_STATUS_TAIL_OVERRIDE_KICS_V9 ===\n"
f"{ind}try:\n"
f"{ind}{step}import os, json\n"
f"{ind}{step}from pathlib import Path\n"
f"{ind}{step}_stage = str(_out.get('stage_name') or '').lower()\n"
f"{ind}{step}_ci = str(_out.get('ci_run_dir') or '')\n"
f"{ind}{step}# fallback: read persisted uireq state to get ci_run_dir\n"
f"{ind}{step}if not _ci:\n"
f"{ind}{step}{step}try:\n"
f"{ind}{step}{step}{step}_st = Path(__file__).resolve().parent / 'out_ci' / 'uireq_v1' / f\"{req_id}.json\"\n"
f"{ind}{step}{step}{step}if _st.exists():\n"
f"{ind}{step}{step}{step}{step}j = json.loads(_st.read_text(encoding='utf-8', errors='ignore') or '{}')\n"
f"{ind}{step}{step}{step}{step}_ci = str(j.get('ci_run_dir') or '')\n"
f"{ind}{step}{step}except Exception:\n"
f"{ind}{step}{step}{step}pass\n"
f"{ind}{step}if _ci:\n"
f"{ind}{step}{step}_klog = os.path.join(_ci, 'kics', 'kics.log')\n"
f"{ind}{step}{step}if os.path.exists(_klog):\n"
f"{ind}{step}{step}{step}rawb = Path(_klog).read_bytes()\n"
f"{ind}{step}{step}{step}if len(rawb) > 65536:\n"
f"{ind}{step}{step}{step}{step}rawb = rawb[-65536:]\n"
f"{ind}{step}{step}{step}raw = rawb.decode('utf-8', errors='ignore').replace('\\\\r','\\\\n')\n"
f"{ind}{step}{step}{step}hb = ''\n"
f"{ind}{step}{step}{step}for ln in reversed(raw.splitlines()):\n"
f"{ind}{step}{step}{step}{step}if '][HB]' in ln and '[KICS_V' in ln:\n"
f"{ind}{step}{step}{step}{step}{step}hb = ln.strip(); break\n"
f"{ind}{step}{step}{step}clean = [x for x in raw.splitlines() if x.strip()]\n"
f"{ind}{step}{step}{step}ktail = '\\\\n'.join(clean[-25:])\n"
f"{ind}{step}{step}{step}if hb and (hb not in ktail):\n"
f"{ind}{step}{step}{step}{step}ktail = hb + '\\\\n' + ktail\n"
f"{ind}{step}{step}{step}_out['kics_tail'] = (ktail or '')[-4096:]\n"
f"{ind}{step}{step}{step}# only override main tail when stage is KICS\n"
f"{ind}{step}{step}{step}if 'kics' in _stage:\n"
f"{ind}{step}{step}{step}{step}_out['tail'] = _out.get('kics_tail','')\n"
f"{ind}except Exception:\n"
f"{ind}{step}pass\n"
f"{ind}# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V9 ===\n"
)

t2 = pat.sub(block, t, count=1)
p.write_text(t2, encoding="utf-8")
print("[OK] upgraded V8 -> V9 (statefile fallback for ci_run_dir)")
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
