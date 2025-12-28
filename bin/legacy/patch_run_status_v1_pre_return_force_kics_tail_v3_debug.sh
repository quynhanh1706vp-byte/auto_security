#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kics_tail_prereturn_v3_${TS}"
echo "[BACKUP] $F.bak_kics_tail_prereturn_v3_${TS}"

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

# remove older V3 blocks if any (global)
txt = "".join(lines)
txt = re.sub(r"(?s)\n?\s*# === VSP_KICS_TAIL_PRE_RETURN_V3_DEBUG ===.*?# === END VSP_KICS_TAIL_PRE_RETURN_V3_DEBUG ===\s*\n?", "\n", txt)
lines = txt.splitlines(True)

# find all handlers decorated with /api/vsp/run_status_v1/<...>
route_re = re.compile(r'^\s*@.*\.route\(\s*["\']/api/vsp/run_status_v1/<[^>]+>["\']', re.M)
all_text = "".join(lines)

# offsets -> line
cum = []
off = 0
for s in lines:
    cum.append(off); off += len(s)

def offset_to_line(o:int)->int:
    lo, hi = 0, len(cum)-1
    while lo < hi:
        mid = (lo+hi+1)//2
        if cum[mid] <= o: lo = mid
        else: hi = mid-1
    return lo

dec_lines = [offset_to_line(m.start()) for m in route_re.finditer(all_text)]
patched_funcs = 0
patched_returns = 0

for dec_i in dec_lines:
    # find def line after decorator
    def_i = None
    def_ind = ""
    def_name = ""
    for j in range(dec_i+1, min(dec_i+40, len(lines))):
        m = re.match(r"^([ \t]*)def\s+([A-Za-z_]\w*)\s*\(\s*req_id\s*\)\s*:\s*$", lines[j])
        if m:
            def_i = j
            def_ind = m.group(1)
            def_name = m.group(2)
            break
    if def_i is None:
        continue

    def_ind_len = len(def_ind)

    # function end
    end_i = len(lines)
    for k in range(def_i+1, len(lines)):
        s = lines[k]
        if re.match(r"^([ \t]*)def\s+\w+\s*\(", s) or re.match(r"^([ \t]*)@\w", s):
            indk = re.match(r"^([ \t]*)", s).group(1)
            if len(indk) <= def_ind_len:
                end_i = k
                break

    func = lines[def_i:end_i]

    # detect indent unit (1 level inside def)
    indent_unit = "    "
    for x in range(1, min(120, len(func))):
        if func[x].strip() == "":
            continue
        m = re.match(r"^([ \t]+)\S", func[x])
        if m:
            indent_unit = m.group(1)[def_ind_len:]
            break

    # find all "return jsonify(" lines inside this function and insert pre-block right above each
    new_func = []
    for s in func:
        st = s.lstrip()
        if st.startswith("return jsonify("):
            ret_ind = s[:len(s)-len(st)]
            blk = []
            blk.append(f"{ret_ind}# === VSP_KICS_TAIL_PRE_RETURN_V3_DEBUG ===\n")
            blk.append(f"{ret_ind}try:\n")
            blk.append(f"{ret_ind}{indent_unit}import os, json\n")
            blk.append(f"{ret_ind}{indent_unit}from pathlib import Path\n")
            blk.append(f"{ret_ind}{indent_unit}NL = chr(10)\n")
            blk.append(f"{ret_ind}{indent_unit}d = None\n")
            blk.append(f"{ret_ind}{indent_unit}# try common local dict vars\n")
            blk.append(f"{ret_ind}{indent_unit}for k in ('_out','out','resp','payload','ret','data','result','st'):\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}v = locals().get(k)\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}if isinstance(v, dict):\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}d = v; break\n")
            blk.append(f"{ret_ind}{indent_unit}# fallback store (if exists)\n")
            blk.append(f"{ret_ind}{indent_unit}if d is None:\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}fb = globals().get('_VSP_FALLBACK_REQ')\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}if isinstance(fb, dict):\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}vv = fb.get(req_id)\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}if isinstance(vv, dict): d = vv\n")
            blk.append(f"{ret_ind}{indent_unit}if isinstance(d, dict):\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}d['_handler'] = '{def_name}'\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}ci = str(d.get('ci_run_dir') or '')\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}# if ci missing, try statefile candidates\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}if not ci:\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}base = Path(__file__).resolve().parent\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}cands = [\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}base / 'out_ci' / 'uireq_v1' / (req_id + '.json'),\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}base / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}base / 'ui' / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}]\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}for stp in cands:\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}if stp.exists():\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}try:\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}t = stp.read_text(encoding='utf-8', errors='ignore') or ''\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}j = json.loads(t) if t.strip() else dict()\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}ci = str(j.get('ci_run_dir') or '')\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}if ci: break\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}except Exception:\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}pass\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}klog = os.path.join(ci, 'kics', 'kics.log')\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}if ci and os.path.exists(klog):\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}rawb = Path(klog).read_bytes()\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}if len(rawb) > 65536: rawb = rawb[-65536:]\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}raw = rawb.decode('utf-8', errors='ignore').replace(chr(13), NL)\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}hb = ''\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}for ln in reversed(raw.splitlines()):\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}if '][HB]' in ln and '[KICS_V' in ln:\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}hb = ln.strip(); break\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}ls2 = [x for x in raw.splitlines() if x.strip()]\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}tail = NL.join(ls2[-30:])\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}if hb and (hb not in tail): tail = hb + NL + tail\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}d['kics_tail'] = tail[-4096:]\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}else:\n")
            blk.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}d['kics_tail'] = '[kics_tail] ci=' + str(ci) + ' exists=' + str(os.path.exists(klog))\n")
            blk.append(f"{ret_ind}except Exception:\n")
            blk.append(f"{ret_ind}{indent_unit}pass\n")
            blk.append(f"{ret_ind}# === END VSP_KICS_TAIL_PRE_RETURN_V3_DEBUG ===\n")
            new_func.extend(blk)
            patched_returns += 1

        new_func.append(s)

    if patched_returns > 0:
        patched_funcs += 1

    lines = lines[:def_i] + new_func + lines[end_i:]

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched funcs={patched_funcs} return_sites={patched_returns}")
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
