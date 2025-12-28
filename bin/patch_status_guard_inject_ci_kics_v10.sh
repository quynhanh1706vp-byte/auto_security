#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_status_guard_ci_kics_v10_${TS}"
echo "[BACKUP] $F.bak_status_guard_ci_kics_v10_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

TAG = "# === VSP_STATUS_GUARD_INJECT_CI_KICS_V10 ==="
if any(TAG in l for l in lines):
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# find guard lines (either same line contains both, or nearby window)
idxs = []
for i,l in enumerate(lines):
    if "run_status_v1" in l and "run_status_v2" in l and "path.startswith" in l:
        idxs.append(i)

if not idxs:
    # fallback: find any line with run_status_v1 and scan next few lines for run_status_v2
    for i in range(len(lines)):
        if "run_status_v1" in lines[i] and "path.startswith" in lines[i]:
            win = "".join(lines[i:i+6])
            if "run_status_v2" in win:
                idxs.append(i)

if not idxs:
    raise SystemExit("[ERR] cannot find guard lines for run_status_v1/v2 (the ones you grepped ~3291/~3377)")

# find top-level def starts
top_defs = [i for i,l in enumerate(lines) if re.match(r'^def\s+\w+\s*\(', l)]
if not top_defs:
    raise SystemExit("[ERR] no top-level def found")

def find_enclosing_top_def(i):
    # nearest top-level def before i
    j = None
    for d in top_defs:
        if d <= i:
            j = d
        else:
            break
    return j

def find_def_end(d):
    # next top-level def after d, else EOF
    for nd in top_defs:
        if nd > d:
            return nd
    return len(lines)

patched = 0
touched = set()

for gi in idxs:
    d = find_enclosing_top_def(gi)
    if d is None:
        continue
    if d in touched:
        continue
    touched.add(d)
    end = find_def_end(d)

    block = lines[d:end]
    if any(TAG in x for x in block):
        continue

    # parse response var name from signature (first arg)
    m = re.match(r'^def\s+(\w+)\s*\((.*?)\)\s*:', block[0].strip())
    if not m:
        continue
    func_name = m.group(1)
    params = m.group(2).strip()
    rvar = None
    if params:
        # pick first parameter name (strip type hints/defaults)
        first = params.split(",")[0].strip()
        # remove type hint / default
        first = first.split(":")[0].strip()
        first = first.split("=")[0].strip()
        if first and first != "*":
            rvar = first
    if not rvar:
        # fallback common names
        rvar = "resp"

    # locate last return in this def block
    ret_idx = None
    for k in range(len(block)-1, -1, -1):
        if re.match(r'^\s*return\b', block[k]):
            ret_idx = k
            break
    if ret_idx is None:
        print(f"[WARN] no return found in {func_name}, skip")
        continue

    ret_indent = re.match(r'^([ \t]*)return\b', block[ret_idx]).group(1)

    inj = []
    inj.append(ret_indent + TAG + "\n")
    inj.append(ret_indent + "try:\n")
    inj.append(ret_indent + "    import json as _json\n")
    inj.append(ret_indent + "    from pathlib import Path as _Path\n")
    inj.append(ret_indent + "    from flask import request as _req\n")
    inj.append(ret_indent + f"    _resp = {rvar}\n")
    inj.append(ret_indent + "    _path = (_req.path or '')\n")
    inj.append(ret_indent + "    if _path.startswith('/api/vsp/run_status_v1/') or _path.startswith('/api/vsp/run_status_v2/'):\n")
    inj.append(ret_indent + "        _rid = (_path.rsplit('/', 1)[-1] or '').split('?', 1)[0].strip()\n")
    inj.append(ret_indent + "        _rid_norm = _rid[4:].strip() if _rid.startswith('RUN_') else _rid\n")
    inj.append(ret_indent + "        _obj = None\n")
    inj.append(ret_indent + "        try:\n")
    inj.append(ret_indent + "            _obj = _resp.get_json(silent=True)\n")
    inj.append(ret_indent + "        except Exception:\n")
    inj.append(ret_indent + "            _obj = None\n")
    inj.append(ret_indent + "        if not isinstance(_obj, dict):\n")
    inj.append(ret_indent + "            try:\n")
    inj.append(ret_indent + "                _raw = (_resp.get_data(as_text=True) or '').lstrip()\n")
    inj.append(ret_indent + "                if _raw.startswith('{'):\n")
    inj.append(ret_indent + "                    _obj = _json.loads(_raw)\n")
    inj.append(ret_indent + "            except Exception:\n")
    inj.append(ret_indent + "                _obj = None\n")
    inj.append(ret_indent + "        if isinstance(_obj, dict):\n")
    inj.append(ret_indent + "            _obj.setdefault('ci_run_dir', None)\n")
    inj.append(ret_indent + "            _obj.setdefault('kics_verdict', '')\n")
    inj.append(ret_indent + "            _obj.setdefault('kics_total', 0)\n")
    inj.append(ret_indent + "            _obj.setdefault('kics_counts', {})\n")
    inj.append(ret_indent + "            _ci = (_obj.get('ci_run_dir') or '').strip()\n")
    inj.append(ret_indent + "            if (not _ci) and _rid_norm:\n")
    inj.append(ret_indent + "                try:\n")
    inj.append(ret_indent + "                    _ci = _vsp_guess_ci_run_dir_from_rid_v33(_rid_norm) or ''\n")
    inj.append(ret_indent + "                except Exception:\n")
    inj.append(ret_indent + "                    _ci = ''\n")
    inj.append(ret_indent + "                if _ci:\n")
    inj.append(ret_indent + "                    _obj['ci_run_dir'] = _ci\n")
    inj.append(ret_indent + "            _ci = (_obj.get('ci_run_dir') or '').strip()\n")
    inj.append(ret_indent + "            if _ci:\n")
    inj.append(ret_indent + "                _ks = _Path(_ci) / 'kics' / 'kics_summary.json'\n")
    inj.append(ret_indent + "                if _ks.is_file():\n")
    inj.append(ret_indent + "                    try:\n")
    inj.append(ret_indent + "                        _jj = _json.loads(_ks.read_text(encoding='utf-8', errors='ignore') or '{}')\n")
    inj.append(ret_indent + "                        if isinstance(_jj, dict):\n")
    inj.append(ret_indent + "                            _obj['kics_verdict'] = str(_jj.get('verdict') or _obj.get('kics_verdict') or '')\n")
    inj.append(ret_indent + "                            try:\n")
    inj.append(ret_indent + "                                _obj['kics_total'] = int(_jj.get('total') or _obj.get('kics_total') or 0)\n")
    inj.append(ret_indent + "                            except Exception:\n")
    inj.append(ret_indent + "                                pass\n")
    inj.append(ret_indent + "                            _cc = _jj.get('counts')\n")
    inj.append(ret_indent + "                            if isinstance(_cc, dict):\n")
    inj.append(ret_indent + "                                _obj['kics_counts'] = _cc\n")
    inj.append(ret_indent + "                    except Exception:\n")
    inj.append(ret_indent + "                        pass\n")
    inj.append(ret_indent + "            try:\n")
    inj.append(ret_indent + "                _resp.set_data(_json.dumps(_obj, ensure_ascii=False))\n")
    inj.append(ret_indent + "                _resp.mimetype = 'application/json'\n")
    inj.append(ret_indent + "            except Exception:\n")
    inj.append(ret_indent + "                pass\n")
    inj.append(ret_indent + "except Exception:\n")
    inj.append(ret_indent + "    pass\n")

    # insert before last return
    new_block = block[:ret_idx] + inj + block[ret_idx:]
    lines = lines[:d] + new_block + lines[end:]

    # update top_defs offsets? easiest: break and re-run once (guards are few)
    patched += 1

# write out
p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched functions containing guard: n={patched}")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
