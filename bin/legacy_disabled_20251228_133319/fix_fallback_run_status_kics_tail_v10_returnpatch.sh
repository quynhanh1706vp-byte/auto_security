#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_before_kics_tail_v10_${TS}"
echo "[BACKUP] $F.bak_before_kics_tail_v10_${TS}"

echo "== [1] ensure vsp_demo_app.py is compilable (auto-restore from backups if needed) =="
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

echo "== [2] patch FINAL return of _fallback_run_status_v1 (V10) =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# find def _fallback_run_status_v1(req_id):
def_i = None
def_ind = ""
for i, s in enumerate(lines):
    m = re.match(r"^([ \t]*)def\s+_fallback_run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", s)
    if m:
        def_i = i
        def_ind = m.group(1)
        break
if def_i is None:
    raise SystemExit("[ERR] cannot find def _fallback_run_status_v1(req_id)")

def_ind_len = len(def_ind)

# find function end: first non-empty line whose indent <= def indent (same block level)
end_i = None
for j in range(def_i + 1, len(lines)):
    s = lines[j]
    if not s.strip():
        continue
    ind = re.match(r"^([ \t]*)", s).group(1)
    if len(ind) <= def_ind_len and not s.lstrip().startswith(("#", "@")):
        end_i = j
        break
if end_i is None:
    end_i = len(lines)

# find LAST "return ... jsonify(...)" inside function
ret_i = None
for j in range(def_i + 1, end_i):
    s = lines[j]
    if "return" in s and "jsonify" in s:
        if re.match(r"^[ \t]*return\b", s):
            ret_i = j
if ret_i is None:
    raise SystemExit("[ERR] cannot find any 'return ... jsonify(...)' in _fallback_run_status_v1")

ret_ind = re.match(r"^([ \t]*)", lines[ret_i]).group(1)

# Build replacement block with EXACT indent = ret_ind
I = ret_ind
S = "    "  # inside try blocks we keep 4 spaces relative; but we always prefix with I anyway

block = []
block.append(f"{I}# === VSP_STATUS_TAIL_OVERRIDE_KICS_V10_RETURNPATCH ===\n")
block.append(f"{I}_out = _vsp_contractize(_VSP_FALLBACK_REQ[req_id])\n")
block.append(f"{I}try:\n")
block.append(f"{I}{S}import os, json\n")
block.append(f"{I}{S}from pathlib import Path\n")
block.append(f"{I}{S}NL = chr(10)\n")
block.append(f"{I}{S}_stage = str(_out.get('stage_name') or '').lower()\n")
block.append(f"{I}{S}_ci = str(_out.get('ci_run_dir') or '')\n")
block.append(f"{I}{S}if not _ci:\n")
block.append(f"{I}{S}{S}try:\n")
block.append(f"{I}{S}{S}{S}_st = (Path(__file__).resolve().parent / 'out_ci' / 'uireq_v1' / (req_id + '.json'))\n")
block.append(f"{I}{S}{S}{S}if _st.exists():\n")
block.append(f"{I}{S}{S}{S}{S}txt = _st.read_text(encoding='utf-8', errors='ignore') or ''\n")
block.append(f"{I}{S}{S}{S}{S}j = json.loads(txt) if txt.strip() else dict()\n")
block.append(f"{I}{S}{S}{S}{S}_ci = str(j.get('ci_run_dir') or '')\n")
block.append(f"{I}{S}{S}except Exception:\n")
block.append(f"{I}{S}{S}{S}pass\n")
block.append(f"{I}{S}if _ci:\n")
block.append(f"{I}{S}{S}_klog = os.path.join(_ci, 'kics', 'kics.log')\n")
block.append(f"{I}{S}{S}if os.path.exists(_klog):\n")
block.append(f"{I}{S}{S}{S}rawb = Path(_klog).read_bytes()\n")
block.append(f"{I}{S}{S}{S}if len(rawb) > 65536:\n")
block.append(f"{I}{S}{S}{S}{S}rawb = rawb[-65536:]\n")
block.append(f"{I}{S}{S}{S}raw = rawb.decode('utf-8', errors='ignore').replace(chr(13), NL)\n")
block.append(f"{I}{S}{S}{S}hb = ''\n")
block.append(f"{I}{S}{S}{S}for ln in reversed(raw.splitlines()):\n")
block.append(f"{I}{S}{S}{S}{S}if '][HB]' in ln and '[KICS_V' in ln:\n")
block.append(f"{I}{S}{S}{S}{S}{S}hb = ln.strip()\n")
block.append(f"{I}{S}{S}{S}{S}{S}break\n")
block.append(f"{I}{S}{S}{S}clean = [x for x in raw.splitlines() if x.strip()]\n")
block.append(f"{I}{S}{S}{S}ktail = NL.join(clean[-25:])\n")
block.append(f"{I}{S}{S}{S}if hb and (hb not in ktail):\n")
block.append(f"{I}{S}{S}{S}{S}ktail = hb + NL + ktail\n")
block.append(f"{I}{S}{S}{S}_out['kics_tail'] = (ktail or '')[-4096:]\n")
block.append(f"{I}{S}{S}{S}if 'kics' in _stage:\n")
block.append(f"{I}{S}{S}{S}{S}_out['tail'] = _out.get('kics_tail','')\n")
block.append(f"{I}except Exception:\n")
block.append(f"{I}{S}pass\n")
block.append(f"{I}# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V10_RETURNPATCH ===\n")
block.append(f"{I}return jsonify(_out), 200\n")

# Replace ONLY that final return line
lines[ret_i:ret_i+1] = block
p.write_text(''.join(lines), encoding="utf-8")
print(f"[OK] patched final return at line {ret_i+1} (func starts line {def_i+1}, ends before line {end_i+1})")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [3] restart 8910 =="
PIDS="$(lsof -ti :8910 2>/dev/null || true)"
if [ -n "${PIDS}" ]; then
  echo "[KILL] 8910 pids: ${PIDS}"
  kill -9 ${PIDS} || true
fi
nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo
echo "[OK] done"
