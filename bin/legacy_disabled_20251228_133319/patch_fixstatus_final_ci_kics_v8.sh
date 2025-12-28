#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fixstatus_final_ci_kics_v8_${TS}"
echo "[BACKUP] $F.bak_fixstatus_final_ci_kics_v8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

FUNC = "_vsp_fix_status_from_body_v16"
TAG  = "# === VSP_FIX_STATUS_FINAL_INJECT_CI_AND_KICS_V8 ==="
path = Path("vsp_demo_app.py")
lines = path.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# 1) find def line
def_re = re.compile(r'^([ \t]*)def\s+' + re.escape(FUNC) + r'\s*\(.*\)\s*(?:->\s*[^:]+)?\s*:\s*$')
i_def = None
indent_def = ""
for i,l in enumerate(lines):
    m = def_re.match(l)
    if m:
        i_def = i
        indent_def = m.group(1)
        break
if i_def is None:
    raise SystemExit(f"[ERR] cannot find def {FUNC}()")

# 2) find function block end by indentation (python rules-ish)
i_end = None
for j in range(i_def+1, len(lines)):
    lj = lines[j]
    if lj.strip() == "":
        continue
    # comment lines are still part of block if indented, otherwise end
    if not (lj.startswith(indent_def) and (len(lj) > len(indent_def)) and lj[len(indent_def)] in (" ", "\t")):
        # dedented => end of function block
        i_end = j
        break
if i_end is None:
    i_end = len(lines)

fn = lines[i_def:i_end]
fn_txt = "".join(fn)
if TAG in fn_txt:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# 3) find last "return" line anywhere inside function
ret_idxs = []
for k in range(1, len(fn)):  # skip def line
    if re.match(r'^\s*return\b', fn[k]):
        ret_idxs.append(k)

if not ret_idxs:
    # function must return something in production; if not found, show tail and fail explicitly
    tail = "".join(fn[-30:])
    print("[ERR] cannot find ANY return in function. Tail(30 lines):\n" + tail)
    raise SystemExit(2)

k_last = ret_idxs[-1]
indent_ret = re.match(r'^([ \t]*)', fn[k_last]).group(1)

inject = (
    f"{indent_ret}{TAG}\n"
    f"{indent_ret}try:\n"
    f"{indent_ret}    import json as _json\n"
    f"{indent_ret}    from pathlib import Path as _Path\n"
    f"{indent_ret}    # pick dict object (prefer local obj if exists)\n"
    f"{indent_ret}    try:\n"
    f"{indent_ret}        _o = obj\n"
    f"{indent_ret}    except Exception:\n"
    f"{indent_ret}        _o = None\n"
    f"{indent_ret}    if not isinstance(_o, dict):\n"
    f"{indent_ret}        try:\n"
    f"{indent_ret}            _o = resp.get_json(silent=True) or {{}}\n"
    f"{indent_ret}        except Exception:\n"
    f"{indent_ret}            _o = {{}}\n"
    f"{indent_ret}\n"
    f"{indent_ret}    # RID from request.path (v1/v2)\n"
    f"{indent_ret}    _path = ''\n"
    f"{indent_ret}    try:\n"
    f"{indent_ret}        _path = (request.path or '')\n"
    f"{indent_ret}    except Exception:\n"
    f"{indent_ret}        _path = ''\n"
    f"{indent_ret}    _rid = ''\n"
    f"{indent_ret}    if '/api/vsp/run_status_v1/' in _path or '/api/vsp/run_status_v2/' in _path:\n"
    f"{indent_ret}        _rid = _path.rsplit('/', 1)[-1].strip()\n"
    f"{indent_ret}    if not _rid:\n"
    f"{indent_ret}        _rid = str(_o.get('rid_norm') or _o.get('request_id') or _o.get('req_id') or '').strip()\n"
    f"{indent_ret}    _rid_norm = _rid\n"
    f"{indent_ret}    if _rid_norm.startswith('RUN_'):\n"
    f"{indent_ret}        _rid_norm = _rid_norm[4:].strip()\n"
    f"{indent_ret}\n"
    f"{indent_ret}    # ensure ci_run_dir\n"
    f"{indent_ret}    if not _o.get('ci_run_dir') and _rid_norm:\n"
    f"{indent_ret}        try:\n"
    f"{indent_ret}            _guess = globals().get('_vsp_guess_ci_run_dir_from_rid_v33')\n"
    f"{indent_ret}            if callable(_guess):\n"
    f"{indent_ret}                _ci = _guess(_rid_norm)\n"
    f"{indent_ret}                if _ci:\n"
    f"{indent_ret}                    _o['ci_run_dir'] = _ci\n"
    f"{indent_ret}        except Exception:\n"
    f"{indent_ret}            pass\n"
    f"{indent_ret}\n"
    f"{indent_ret}    # defaults\n"
    f"{indent_ret}    _o.setdefault('kics_verdict', '')\n"
    f"{indent_ret}    _o.setdefault('kics_total', 0)\n"
    f"{indent_ret}    _o.setdefault('kics_counts', {{}})\n"
    f"{indent_ret}\n"
    f"{indent_ret}    # load kics_summary.json\n"
    f"{indent_ret}    _ci_dir = _o.get('ci_run_dir')\n"
    f"{indent_ret}    if _ci_dir:\n"
    f"{indent_ret}        _ks = _Path(str(_ci_dir)) / 'kics' / 'kics_summary.json'\n"
    f"{indent_ret}        if _ks.is_file():\n"
    f"{indent_ret}            try:\n"
    f"{indent_ret}                _j = _json.loads(_ks.read_text(encoding='utf-8', errors='ignore') or '{{}}')\n"
    f"{indent_ret}                if isinstance(_j, dict):\n"
    f"{indent_ret}                    _o['kics_verdict'] = str(_j.get('verdict') or _o.get('kics_verdict') or '')\n"
    f"{indent_ret}                    _o['kics_total']   = int(_j.get('total') or _o.get('kics_total') or 0)\n"
    f"{indent_ret}                    _c = _j.get('counts')\n"
    f"{indent_ret}                    if isinstance(_c, dict):\n"
    f"{indent_ret}                        _o['kics_counts'] = _c\n"
    f"{indent_ret}            except Exception:\n"
    f"{indent_ret}                pass\n"
    f"{indent_ret}\n"
    f"{indent_ret}    # write back to local obj if possible\n"
    f"{indent_ret}    try:\n"
    f"{indent_ret}        obj.clear(); obj.update(_o)\n"
    f"{indent_ret}    except Exception:\n"
    f"{indent_ret}        pass\n"
    f"{indent_ret}\n"
    f"{indent_ret}    # if function returns resp, ensure resp JSON carries injected fields\n"
    f"{indent_ret}    try:\n"
    f"{indent_ret}        _mk = globals().get('_vsp_json_v16')\n"
    f"{indent_ret}        if callable(_mk):\n"
    f"{indent_ret}            resp = _mk(_o, getattr(resp, 'status_code', None))\n"
    f"{indent_ret}        else:\n"
    f"{indent_ret}            resp.set_data(_json.dumps(_o, ensure_ascii=False))\n"
    f"{indent_ret}            resp.mimetype = 'application/json'\n"
    f"{indent_ret}    except Exception:\n"
    f"{indent_ret}        pass\n"
    f"{indent_ret}except Exception:\n"
    f"{indent_ret}    pass\n"
)

# insert just before last return line
fn2 = fn[:k_last] + [inject] + fn[k_last:]
lines2 = lines[:i_def] + fn2 + lines[i_end:]
path.write_text("".join(lines2), encoding="utf-8")

print("[OK] injected before LAST return:", k_last, "indent_ret_len=", len(indent_ret))
print("[OK] last return line =", fn[k_last].strip())
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] run_status_v2 should now show ci_run_dir + kics_* =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
