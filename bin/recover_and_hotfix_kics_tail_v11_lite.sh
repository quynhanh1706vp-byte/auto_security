#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_before_kics_tail_v11lite_${TS}"
echo "[BACKUP] $F.bak_before_kics_tail_v11lite_${TS}"

echo "== [1] ensure file compilable (auto-restore if needed) =="
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

echo "== [2] hotfix: insert KICS tail override BEFORE final return in _fallback_run_status_v1 (V11_LITE) =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# Locate def _fallback_run_status_v1(req_id):
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

# Find end of function by indent drop (best effort)
def_body_i = None
for j in range(def_i + 1, len(lines)):
    if lines[j].strip() == "":
        continue
    if lines[j].startswith(def_ind) and len(lines[j]) > len(def_ind):
        def_body_i = j
        break
if def_body_i is None:
    raise SystemExit("[ERR] cannot find body of _fallback_run_status_v1")

# Deduce indent unit from first statement line
body_ind = re.match(r"^([ \t]+)", lines[def_body_i]).group(1)
indent_unit = body_ind[len(def_ind):]  # could be "\t" or "    " or mixed
if indent_unit == "":
    indent_unit = "    "

# Find the FINAL 'return jsonify(_out), 200' inside the function
# We'll search between def_i..next indent drop
end_i = len(lines)
for k in range(def_i + 1, len(lines)):
    s = lines[k]
    if s.strip() == "":
        continue
    cur_ind = re.match(r"^([ \t]*)", s).group(1)
    if len(cur_ind) <= len(def_ind) and k > def_i + 1 and re.match(r"^\s*(def|@|try:|except|class)\b", s):
        end_i = k
        break

ret_i = None
ret_ind = None
for k in range(def_i + 1, end_i):
    m = re.match(r"^([ \t]*)return\s+jsonify\(\s*_out\s*\)\s*,\s*200\s*$", lines[k].rstrip("\n"))
    if m:
        ret_i = k
        ret_ind = m.group(1)
# If not found, fallback: last return line in function
if ret_i is None:
    for k in range(def_i + 1, end_i):
        if re.match(r"^([ \t]*)return\s+jsonify\(", lines[k]):
            ret_i = k
            ret_ind = re.match(r"^([ \t]*)", lines[k]).group(1)
if ret_i is None:
    raise SystemExit("[ERR] cannot find any return jsonify(...) in _fallback_run_status_v1")

# Remove any previous V11_LITE block (idempotent)
txt_func = "".join(lines[def_i:end_i])
txt_func2 = re.sub(
    r"\n?[ \t]*# === VSP_KICS_TAIL_HOTFIX_V11_LITE ===[\s\S]*?# === END VSP_KICS_TAIL_HOTFIX_V11_LITE ===\n?",
    "\n",
    txt_func,
    flags=re.S
)
lines[def_i:end_i] = txt_func2.splitlines(True)

# Recompute positions after removal
# re-read slice
txt = "".join(lines)
lines = txt.splitlines(True)

# re-find function + return again (quick)
def_i = None
def_ind = ""
for i, s in enumerate(lines):
    m = re.match(r"^([ \t]*)def\s+_fallback_run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", s)
    if m:
        def_i = i
        def_ind = m.group(1)
        break
if def_i is None:
    raise SystemExit("[ERR] cannot re-find def after cleanup")

end_i = len(lines)
for k in range(def_i + 1, len(lines)):
    s = lines[k]
    if s.strip() == "":
        continue
    cur_ind = re.match(r"^([ \t]*)", s).group(1)
    if len(cur_ind) <= len(def_ind) and k > def_i + 1 and re.match(r"^\s*(def|@|try:|except|class)\b", s):
        end_i = k
        break

# find return jsonify(_out),200 again
ret_i = None
ret_ind = None
for k in range(def_i + 1, end_i):
    m = re.match(r"^([ \t]*)return\s+jsonify\(\s*_out\s*\)\s*,\s*200\s*$", lines[k].rstrip("\n"))
    if m:
        ret_i = k
        ret_ind = m.group(1)
if ret_i is None:
    # last return jsonify
    for k in range(def_i + 1, end_i):
        if re.match(r"^([ \t]*)return\s+jsonify\(", lines[k]):
            ret_i = k
            ret_ind = re.match(r"^([ \t]*)", lines[k]).group(1)
if ret_i is None:
    raise SystemExit("[ERR] cannot re-find return in function")

# Ensure _out exists: if not present in last ~120 lines above return, insert it just before hotfix
window_start = max(def_i, ret_i - 140)
window = "".join(lines[window_start:ret_i])
has_out = re.search(r"(?m)^\s*_out\s*=\s*", window) is not None

I0 = ret_ind
I1 = ret_ind + indent_unit
I2 = I1 + indent_unit
I3 = I2 + indent_unit
I4 = I3 + indent_unit

hot = []
hot.append(f"{I0}# === VSP_KICS_TAIL_HOTFIX_V11_LITE ===\n")
if not has_out:
    hot.append(f"{I0}_out = _vsp_contractize(_VSP_FALLBACK_REQ[req_id])\n")
hot.append(f"{I0}try:\n")
hot.append(f"{I1}import os, json\n")
hot.append(f"{I1}from pathlib import Path\n")
hot.append(f"{I1}NL = chr(10)\n")
hot.append(f"{I1}_stage = str(_out.get('stage_name') or '').lower()\n")
hot.append(f"{I1}_ci = str(_out.get('ci_run_dir') or _out.get('ci_dir') or '')\n")
hot.append(f"{I1}if not _ci:\n")
hot.append(f"{I2}base = Path(__file__).resolve().parent\n")
hot.append(f"{I2}cands = [\n")
hot.append(f"{I3}base / 'out_ci' / 'uireq_v1' / (req_id + '.json'),\n")
hot.append(f"{I3}base / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),\n")
hot.append(f"{I3}base / 'ui' / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),\n")
hot.append(f"{I3}Path('/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1') / (req_id + '.json'),\n")
hot.append(f"{I3}Path('/home/test/Data/SECURITY_BUNDLE/ui/ui/out_ci/uireq_v1') / (req_id + '.json'),\n")
hot.append(f"{I2}]\n")
hot.append(f"{I2}for st in cands:\n")
hot.append(f"{I3}try:\n")
hot.append(f"{I4}if st.exists():\n")
hot.append(f"{I4}{indent_unit}txt = st.read_text(encoding='utf-8', errors='ignore') or ''\n")
hot.append(f"{I4}{indent_unit}j = json.loads(txt) if txt.strip() else dict()\n")
hot.append(f"{I4}{indent_unit}_ci = str(j.get('ci_run_dir') or j.get('ci_dir') or '')\n")
hot.append(f"{I4}{indent_unit}if _ci:\n")
hot.append(f"{I4}{indent_unit}{indent_unit}_out['ci_run_dir'] = _ci\n")
hot.append(f"{I4}{indent_unit}{indent_unit}break\n")
hot.append(f"{I3}except Exception:\n")
hot.append(f"{I4}pass\n")
hot.append(f"{I1}if _ci:\n")
hot.append(f"{I2}klog = os.path.join(_ci, 'kics', 'kics.log')\n")
hot.append(f"{I2}if os.path.exists(klog):\n")
hot.append(f"{I3}rawb = Path(klog).read_bytes()\n")
hot.append(f"{I3}if len(rawb) > 65536:\n")
hot.append(f"{I4}rawb = rawb[-65536:]\n")
hot.append(f"{I3}raw = rawb.decode('utf-8', errors='ignore').replace(chr(13), NL)\n")
hot.append(f"{I3}hb = ''\n")
hot.append(f"{I3}for ln in reversed(raw.splitlines()):\n")
hot.append(f"{I4}if '][HB]' in ln and '[KICS_V' in ln:\n")
hot.append(f"{I4}{indent_unit}hb = ln.strip(); break\n")
hot.append(f"{I3}clean = [x for x in raw.splitlines() if x.strip()]\n")
hot.append(f"{I3}ktail = NL.join(clean[-25:])\n")
hot.append(f"{I3}if hb and (hb not in ktail):\n")
hot.append(f"{I4}ktail = hb + NL + ktail\n")
hot.append(f"{I3}_out['kics_tail'] = (ktail or '')[-4096:]\n")
hot.append(f"{I3}if 'kics' in _stage:\n")
hot.append(f"{I4}_out['tail'] = _out.get('kics_tail','')\n")
hot.append(f"{I0}except Exception:\n")
hot.append(f"{I1}pass\n")
hot.append(f"{I0}# === END VSP_KICS_TAIL_HOTFIX_V11_LITE ===\n")

lines[ret_i:ret_i] = hot
p.write_text("".join(lines), encoding="utf-8")
print("[OK] inserted V11_LITE before final return using detected indent_unit:", repr(indent_unit))
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
