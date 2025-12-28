#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "== [1] backup current =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_tail_kics_v6_${TS}"
echo "[BACKUP] $F.bak_fix_tail_kics_v6_${TS}"

echo "== [2] ensure file is compilable (auto-restore from backups if needed) =="
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

echo "== [3] patch ONLY _fallback_run_status_v1: tail <- kics.log + HB (V6_FIXED_SAFE) =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# find def _fallback_run_status_v1(req_id):
m_def = None
for i, s in enumerate(lines):
    if re.match(r"^([ \t]*)def\s+_fallback_run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", s):
        m_def = (i, re.match(r"^([ \t]*)", s).group(1))
        break

if not m_def:
    raise SystemExit("[ERR] cannot find: def _fallback_run_status_v1(req_id):")

start_i, def_ind = m_def
def_ind_len = len(def_ind)

# body indent = indent of first non-empty line after def
body_ind = None
for j in range(start_i+1, min(len(lines), start_i+3000)):
    if lines[j].strip() == "":
        continue
    ind = re.match(r"^([ \t]*)", lines[j]).group(1)
    if len(ind) > def_ind_len:
        body_ind = ind
        break
if body_ind is None:
    body_ind = def_ind + "    "

# indent step (avoid TabError)
STEP = "\t" if ("\t" in body_ind and body_ind.replace("\t","") == "") else "    "

# find end of function: first non-empty line with indent <= def_ind (dedent)
end_i = len(lines)
for j in range(start_i+1, len(lines)):
    if lines[j].strip() == "":
        continue
    ind = re.match(r"^([ \t]*)", lines[j]).group(1)
    if len(ind) <= def_ind_len:
        end_i = j
        break

func = lines[start_i:end_i]

# remove any previous injected blocks ONLY within this function
def _strip_block(func_lines, tag_prefix):
    out = []
    i = 0
    while i < len(func_lines):
        s = func_lines[i]
        if tag_prefix in s:
            # drop until END marker
            i += 1
            while i < len(func_lines) and ("# === END " not in func_lines[i]):
                i += 1
            if i < len(func_lines):
                i += 1
            continue
        out.append(s)
        i += 1
    return out

# remove old V5/V6 attempts (both append hb + prefer kics)
func = _strip_block(func, "VSP_STATUS_TAIL_APPEND_KICS_HB_")
func = _strip_block(func, "VSP_STATUS_TAIL_PREFER_KICS_LOG_")

# choose insertion point: BEFORE last 'return' in this function
ins_at = None
for k in range(len(func)-1, -1, -1):
    if re.match(r"^[ \t]*return\b", func[k]):
        ins_at = k
        break
if ins_at is None:
    ins_at = len(func)

TAG = "# === VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED_SAFE ==="
END = "# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED_SAFE ==="

b = []
b.append(f"{body_ind}{TAG}\n")
b.append(f"{body_ind}try:\n")
b.append(f"{body_ind}{STEP}import os\n")
b.append(f"{body_ind}{STEP}st = _VSP_FALLBACK_REQ.get(req_id) or {{}}\n")
b.append(f"{body_ind}{STEP}_stage = str(st.get('stage_name') or '').lower()\n")
b.append(f"{body_ind}{STEP}_ci = str(st.get('ci_run_dir') or '')\n")
b.append(f"{body_ind}{STEP}if ('kics' in _stage) and _ci:\n")
b.append(f"{body_ind}{STEP}{STEP}_klog = os.path.join(_ci, 'kics', 'kics.log')\n")
b.append(f"{body_ind}{STEP}{STEP}if os.path.exists(_klog):\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}with open(_klog, 'rb') as fh:\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}{STEP}_rawb = fh.read()\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}if len(_rawb) > 65536:\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}{STEP}_rawb = _rawb[-65536:]\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}_raw = _rawb.decode('utf-8', errors='ignore').replace('\\r','\\n')\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}_hb = ''\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}for _ln in reversed(_raw.splitlines()):\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}{STEP}if '][HB]' in _ln and '[KICS_V' in _ln:\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}{STEP}{STEP}_hb = _ln.strip()\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}{STEP}{STEP}break\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}_lines = [x for x in _raw.splitlines() if x.strip()]\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}_tail = '\\n'.join(_lines[-25:])\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}if _hb and (_hb not in _tail):\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}{STEP}_tail = _hb + '\\n' + _tail\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}st['tail'] = (_tail or '')[-4096:]\n")
b.append(f"{body_ind}{STEP}{STEP}{STEP}_VSP_FALLBACK_REQ[req_id] = st\n")
b.append(f"{body_ind}except Exception:\n")
b.append(f"{body_ind}{STEP}pass\n")
b.append(f"{body_ind}{END}\n")

func2 = func[:ins_at] + b + func[ins_at:]
new_lines = lines[:start_i] + func2 + lines[end_i:]

p.write_text("".join(new_lines), encoding="utf-8")
print(f"[OK] patched in-function only. start={start_i+1} end={end_i} insert_before_return_line~{start_i+ins_at+1}")
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
