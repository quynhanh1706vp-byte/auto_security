#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_force_kics_tail_v2_${TS}"
echo "[BACKUP] $F.bak_fix_force_kics_tail_v2_${TS}"

python3 - <<'PY'
import re, json
from pathlib import Path

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# find def _fallback_run_status_v1
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

# find function end (next top-level / same-or-less indent non-decorator line)
end = len(lines)
def_len = len(def_ind)
for j in range(def_i+1, len(lines)):
    s = lines[j]
    if not s.strip():
        continue
    ind = re.match(r"^([ \t]*)", s).group(1)
    if len(ind) <= def_len and not s.lstrip().startswith(("#", "@")):
        end = j
        break

# find last return jsonify(...) inside function
ret_i = None
for j in range(end-1, def_i, -1):
    if "return" in lines[j] and "jsonify" in lines[j]:
        ret_i = j
        break
if ret_i is None:
    raise SystemExit("[ERR] cannot find return jsonify(...) in _fallback_run_status_v1")

ind_ret = re.match(r"^([ \t]*)", lines[ret_i]).group(1)
unit = "    " if "\t" not in ind_ret else "\t"  # conservative

block = []
block.append(ind_ret + "# === VSP_FORCE_KICS_TAIL_V2 ===\n")
block.append(ind_ret + "_out = _vsp_contractize(_VSP_FALLBACK_REQ[req_id])\n")
block.append(ind_ret + "try:\n")
block.append(ind_ret + unit + "import os, json\n")
block.append(ind_ret + unit + "from pathlib import Path\n")
block.append(ind_ret + unit + "NL = chr(10)\n")
block.append(ind_ret + unit + "_ci = str(_out.get('ci_run_dir') or '')\n")
block.append(ind_ret + unit + "if not _ci:\n")
block.append(ind_ret + unit + unit + "cands = [\n")
block.append(ind_ret + unit + unit + unit + "(Path(__file__).resolve().parent / 'out_ci' / 'uireq_v1' / (req_id + '.json')),\n")
block.append(ind_ret + unit + unit + unit + "(Path(__file__).resolve().parent / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json')),\n")
block.append(ind_ret + unit + unit + unit + "(Path(__file__).resolve().parent / 'ui' / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json')),\n")
block.append(ind_ret + unit + unit + "]\n")
block.append(ind_ret + unit + unit + "for _st in cands:\n")
block.append(ind_ret + unit + unit + unit + "if _st.exists():\n")
block.append(ind_ret + unit + unit + unit + unit + "txt = _st.read_text(encoding='utf-8', errors='ignore') or ''\n")
block.append(ind_ret + unit + unit + unit + unit + "j = json.loads(txt) if txt.strip() else {}\n")
block.append(ind_ret + unit + unit + unit + unit + "_ci = str(j.get('ci_run_dir') or '')\n")
block.append(ind_ret + unit + unit + unit + unit + "break\n")
block.append(ind_ret + unit + "if _ci:\n")
block.append(ind_ret + unit + unit + "_klog = os.path.join(_ci, 'kics', 'kics.log')\n")
block.append(ind_ret + unit + unit + "if os.path.exists(_klog):\n")
block.append(ind_ret + unit + unit + unit + "rawb = Path(_klog).read_bytes()\n")
block.append(ind_ret + unit + unit + unit + "if len(rawb) > 65536:\n")
block.append(ind_ret + unit + unit + unit + unit + "rawb = rawb[-65536:]\n")
block.append(ind_ret + unit + unit + unit + "raw = rawb.decode('utf-8', errors='ignore').replace(chr(13), NL)\n")
block.append(ind_ret + unit + unit + unit + "hb = ''\n")
block.append(ind_ret + unit + unit + unit + "for ln in reversed(raw.splitlines()):\n")
block.append(ind_ret + unit + unit + unit + unit + "if '][HB]' in ln and '[KICS_V' in ln:\n")
block.append(ind_ret + unit + unit + unit + unit + unit + "hb = ln.strip(); break\n")
block.append(ind_ret + unit + unit + unit + "lines2 = [x for x in raw.splitlines() if x.strip()]\n")
block.append(ind_ret + unit + unit + unit + "tail = NL.join(lines2[-60:])\n")
block.append(ind_ret + unit + unit + unit + "if hb and hb not in tail:\n")
block.append(ind_ret + unit + unit + unit + unit + "tail = hb + NL + tail\n")
block.append(ind_ret + unit + unit + unit + "_out['kics_tail'] = tail[-4096:]\n")
block.append(ind_ret + "except Exception:\n")
block.append(ind_ret + unit + "pass\n")
block.append(ind_ret + "# === END VSP_FORCE_KICS_TAIL_V2 ===\n")
block.append(ind_ret + "return jsonify(_out), 200\n")

lines[ret_i:ret_i+1] = block
p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] replaced final return at line {ret_i+1} with FORCE_KICS_TAIL_V2")
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
