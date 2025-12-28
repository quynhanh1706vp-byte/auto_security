#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_force_kics_tail_all_${TS}"
echo "[BACKUP] $F.bak_force_kics_tail_all_${TS}"

# ensure compilable by auto-restore if needed
if ! python3 -m py_compile "$F" >/dev/null 2>&1; then
  echo "[WARN] current file does NOT compile. searching backups..."
  CANDS="$(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true)"
  [ -n "$CANDS" ] || { echo "[ERR] no backups found: vsp_demo_app.py.bak_*"; exit 2; }
  OK_BAK=""
  for B in $CANDS; do
    cp -f "$B" "$F"
    if python3 -m py_compile "$F" >/dev/null 2>&1; then OK_BAK="$B"; break; fi
  done
  [ -n "$OK_BAK" ] || { echo "[ERR] no compilable backup found"; exit 3; }
  echo "[OK] restored $F <= $OK_BAK"
fi

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# remove older V2 tags if any
txt = "".join(lines)
txt = re.sub(r"(?s)\n?\s*# === VSP_FORCE_KICS_TAIL_BY_ROUTE_V2 ===.*?# === END VSP_FORCE_KICS_TAIL_BY_ROUTE_V2 ===\s*\n?", "\n", txt)
lines = txt.splitlines(True)

# find all decorators for run_status_v1 route
route_re = re.compile(r'''^\s*@.*\.route\(\s*["']\/api\/vsp\/run_status_v1\/<[^>]+>["']''', re.M)

# indices of decorator lines
dec_idxs = [m.start() for m in route_re.finditer("".join(lines))]
# map start offsets to line numbers
# build cumulative offsets
cum = []
off = 0
for i, s in enumerate(lines):
    cum.append(off)
    off += len(s)

def offset_to_line(o: int) -> int:
    # last cum <= o
    lo, hi = 0, len(cum)-1
    while lo < hi:
        mid = (lo+hi+1)//2
        if cum[mid] <= o: lo = mid
        else: hi = mid-1
    return lo

dec_lines = [offset_to_line(o) for o in dec_idxs]

TAG_BEG = "# === VSP_FORCE_KICS_TAIL_BY_ROUTE_V2 ==="
TAG_END = "# === END VSP_FORCE_KICS_TAIL_BY_ROUTE_V2 ==="

patched_n = 0

for dec_i in dec_lines:
    # find next def after decorator
    def_i = None
    for j in range(dec_i+1, min(dec_i+30, len(lines))):
        m = re.match(r"^([ \t]*)def\s+([A-Za-z_]\w*)\s*\(\s*req_id\s*\)\s*:\s*$", lines[j])
        if m:
            def_i = j
            def_ind = m.group(1)
            def_name = m.group(2)
            break
    if def_i is None:
        continue

    def_ind_len = len(def_ind)

    # find function end (next def/decorator at indent <= def_ind)
    end_i = len(lines)
    for k in range(def_i+1, len(lines)):
        s = lines[k]
        if re.match(r"^([ \t]*)def\s+\w+\s*\(", s) or re.match(r"^([ \t]*)@\w", s):
            indk = re.match(r"^([ \t]*)", s).group(1)
            if len(indk) <= def_ind_len:
                end_i = k
                break

    func = lines[def_i:end_i]

    # find last return jsonify(...), 200
    ret_idx = None
    ret_line = None
    for idx in range(len(func)-1, -1, -1):
        s = func[idx].strip()
        if s.startswith("return jsonify(") and re.search(r"\)\s*,\s*200\s*$", s):
            ret_idx = idx
            ret_line = func[idx]
            break
    if ret_idx is None:
        continue

    ret_ind = re.match(r"^([ \t]*)", ret_line).group(1)
    # detect indent unit
    indent_unit = "    "
    for x in range(1, min(80, len(func))):
        if func[x].strip() == "":
            continue
        m = re.match(r"^([ \t]+)\S", func[x])
        if m:
            indent_unit = m.group(1)[def_ind_len:]
        break

    # extract expr inside jsonify(...)
    s = ret_line.strip()
    inner = s[len("return jsonify("):]
    expr = re.sub(r"\)\s*,\s*200\s*$", "", inner).rstrip()

    patch = []
    patch.append(f"{ret_ind}{TAG_BEG}\n")
    patch.append(f"{ret_ind}_out = {expr}\n")
    patch.append(f"{ret_ind}try:\n")
    patch.append(f"{ret_ind}{indent_unit}import os\n")
    patch.append(f"{ret_ind}{indent_unit}from pathlib import Path\n")
    patch.append(f"{ret_ind}{indent_unit}NL = chr(10)\n")
    patch.append(f"{ret_ind}{indent_unit}if isinstance(_out, dict):\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}ci = str(_out.get('ci_run_dir') or '')\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}if ci:\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}klog = os.path.join(ci, 'kics', 'kics.log')\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}if os.path.exists(klog):\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}rawb = Path(klog).read_bytes()\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}if len(rawb) > 65536:\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}rawb = rawb[-65536:]\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}raw = rawb.decode('utf-8', errors='ignore').replace(chr(13), NL)\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}hb = ''\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}for ln in reversed(raw.splitlines()):\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}if '][HB]' in ln and '[KICS_V' in ln:\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}hb = ln.strip(); break\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}lines2 = [x for x in raw.splitlines() if x.strip()]\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}tail = NL.join(lines2[-30:])\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}if hb and (hb not in tail):\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}tail = hb + NL + tail\n")
    patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}_out['kics_tail'] = tail[-4096:]\n")
    patch.append(f"{ret_ind}except Exception:\n")
    patch.append(f"{ret_ind}{indent_unit}pass\n")
    patch.append(f"{ret_ind}{TAG_END}\n")
    patch.append(f"{ret_ind}return jsonify(_out), 200\n")

    new_func = func[:ret_idx] + patch + func[ret_idx+1:]
    lines = lines[:def_i] + new_func + lines[end_i:]
    patched_n += 1

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched handlers by route: {patched_n}")
PY

python3 -m py_compile "$F" >/dev/null
echo "[OK] py_compile OK"

echo "== restart 8910 =="
pkill -f "vsp_demo_app.py" >/dev/null 2>&1 || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz || true
echo
echo "[OK] done"
