#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fixstatus_final_ci_kics_v7_${TS}"
echo "[BACKUP] $F.bak_fixstatus_final_ci_kics_v7_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

path = Path("vsp_demo_app.py")
t = path.read_text(encoding="utf-8", errors="ignore")

FUNC = "_vsp_fix_status_from_body_v16"
TAG  = "# === VSP_FIX_STATUS_FINAL_INJECT_CI_AND_KICS_V7 ==="

m = re.search(r'(?m)^(?P<indent>\s*)def\s+' + re.escape(FUNC) + r'\s*\([^)]*\)\s*(?:->\s*[^:]+)?\s*:\s*$', t)
if not m:
    print("[ERR] cannot find func:", FUNC)
    raise SystemExit(2)

indent = m.group("indent")
start  = m.start()

m_next = re.search(r'(?m)^' + re.escape(indent) + r'def\s+\w+\s*\(', t[m.end():])
end = (m.end() + m_next.start()) if m_next else len(t)

fn = t[start:end]
if TAG in fn:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

body_indent = indent + "    "

# find last "return ..." at body indent (avoid nested returns deeper than body)
ret_matches = list(re.finditer(r'(?m)^' + re.escape(body_indent) + r'return\s+.+$', fn))
if not ret_matches:
    print("[ERR] cannot find final return in", FUNC)
    raise SystemExit(3)

last_ret = ret_matches[-1]
ins_pos = last_ret.start()

inject = (
    f"{body_indent}{TAG}\n"
    f"{body_indent}try:\n"
    f"{body_indent}    import json as _json\n"
    f"{body_indent}    from pathlib import Path as _Path\n"
    f"{body_indent}    try:\n"
    f"{body_indent}        _obj = obj  # prefer parsed obj if exists\n"
    f"{body_indent}    except Exception:\n"
    f"{body_indent}        _obj = None\n"
    f"{body_indent}    if not isinstance(_obj, dict):\n"
    f"{body_indent}        try:\n"
    f"{body_indent}            _obj = resp.get_json(silent=True) or {{}}\n"
    f"{body_indent}        except Exception:\n"
    f"{body_indent}            _obj = {{}}\n"
    f"{body_indent}\n"
    f"{body_indent}    # derive RID from request.path (works for v1 + v2)\n"
    f"{body_indent}    _path = ''\n"
    f"{body_indent}    try:\n"
    f"{body_indent}        _path = (request.path or '')\n"
    f"{body_indent}    except Exception:\n"
    f"{body_indent}        _path = ''\n"
    f"{body_indent}\n"
    f"{body_indent}    _rid = ''\n"
    f"{body_indent}    if '/api/vsp/run_status_v1/' in _path or '/api/vsp/run_status_v2/' in _path:\n"
    f"{body_indent}        _rid = _path.rsplit('/', 1)[-1].strip()\n"
    f"{body_indent}    if not _rid:\n"
    f"{body_indent}        _rid = (_obj.get('rid_norm') or _obj.get('request_id') or _obj.get('req_id') or '').strip()\n"
    f"{body_indent}\n"
    f"{body_indent}    # normalize rid: accept RUN_<rid>\n"
    f"{body_indent}    _rid_norm = _rid\n"
    f"{body_indent}    if _rid_norm.startswith('RUN_'):\n"
    f"{body_indent}        _rid_norm = _rid_norm[4:].strip()\n"
    f"{body_indent}\n"
    f"{body_indent}    # ensure ci_run_dir\n"
    f"{body_indent}    if not _obj.get('ci_run_dir') and _rid_norm:\n"
    f"{body_indent}        try:\n"
    f"{body_indent}            _guess_fn = globals().get('_vsp_guess_ci_run_dir_from_rid_v33')\n"
    f"{body_indent}            if callable(_guess_fn):\n"
    f"{body_indent}                _ci = _guess_fn(_rid_norm)\n"
    f"{body_indent}                if _ci:\n"
    f"{body_indent}                    _obj['ci_run_dir'] = _ci\n"
    f"{body_indent}        except Exception:\n"
    f"{body_indent}            pass\n"
    f"{body_indent}\n"
    f"{body_indent}    # inject kics_summary if available\n"
    f"{body_indent}    _obj.setdefault('kics_verdict', '')\n"
    f"{body_indent}    _obj.setdefault('kics_total', 0)\n"
    f"{body_indent}    _obj.setdefault('kics_counts', {{}})\n"
    f"{body_indent}    _ci_dir = _obj.get('ci_run_dir')\n"
    f"{body_indent}    if _ci_dir:\n"
    f"{body_indent}        _ks = _Path(str(_ci_dir)) / 'kics' / 'kics_summary.json'\n"
    f"{body_indent}        if _ks.is_file():\n"
    f"{body_indent}            try:\n"
    f"{body_indent}                _j = _json.loads(_ks.read_text(encoding='utf-8', errors='ignore') or '{{}}')\n"
    f"{body_indent}                if isinstance(_j, dict):\n"
    f"{body_indent}                    _obj['kics_verdict'] = str(_j.get('verdict') or _obj.get('kics_verdict') or '')\n"
    f"{body_indent}                    _obj['kics_total']   = int(_j.get('total') or _obj.get('kics_total') or 0)\n"
    f"{body_indent}                    _c = _j.get('counts')\n"
    f"{body_indent}                    if isinstance(_c, dict):\n"
    f"{body_indent}                        _obj['kics_counts'] = _c\n"
    f"{body_indent}            except Exception:\n"
    f"{body_indent}                pass\n"
    f"{body_indent}\n"
    f"{body_indent}    # write-back to local 'obj' if it exists\n"
    f"{body_indent}    try:\n"
    f"{body_indent}        obj.clear(); obj.update(_obj)\n"
    f"{body_indent}    except Exception:\n"
    f"{body_indent}        pass\n"
    f"{body_indent}except Exception:\n"
    f"{body_indent}    pass\n"
)

fn2 = fn[:ins_pos] + inject + fn[ins_pos:]
t2  = t[:start] + fn2 + t[end:]
path.write_text(t2, encoding="utf-8")
print("[OK] injected final CI+KICS into", FUNC)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] run_status_v2 should now show ci_run_dir + kics_* =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
