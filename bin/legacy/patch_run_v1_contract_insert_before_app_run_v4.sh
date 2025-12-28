#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_before_apprun_v4_${TS}"
echo "[BACKUP] $F.bak_runv1_before_apprun_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

marker = "VSP_RUNV1_CONTRACT_BEFORE_APP_RUN_V4"
if marker in txt:
    print("[OK] already patched")
    raise SystemExit(0)

# find LAST app.run( ... )
m_all = list(re.finditer(r'^(?P<indent>\s*)app\.run\s*\(', txt, flags=re.M))
if not m_all:
    print("[ERR] cannot find app.run(")
    raise SystemExit(2)

m = m_all[-1]
indent = m.group("indent")
ins = m.start()

block = (
f"{indent}# === {marker} ===\n"
f"{indent}try:\n"
f"{indent}    from flask import jsonify\n"
f"{indent}    # wrap /api/vsp/run_v1 response to always include request_id + rid\n"
f"{indent}    _ep = None\n"
f"{indent}    try:\n"
f"{indent}        for r in app.url_map.iter_rules():\n"
f"{indent}            if getattr(r, 'rule', None) == '/api/vsp/run_v1':\n"
f"{indent}                _ep = r.endpoint\n"
f"{indent}                break\n"
f"{indent}    except Exception:\n"
f"{indent}        _ep = None\n"
f"{indent}\n"
f"{indent}    if _ep and _ep in app.view_functions:\n"
f"{indent}        _orig = app.view_functions[_ep]\n"
f"{indent}\n"
f"{indent}        def _wrapped_run_v1_contract_v4(*args, **kwargs):\n"
f"{indent}            ret = _orig(*args, **kwargs)\n"
f"{indent}            resp, code, headers = ret, None, None\n"
f"{indent}            if isinstance(ret, tuple) and len(ret) >= 1:\n"
f"{indent}                resp = ret[0]\n"
f"{indent}                if len(ret) >= 2: code = ret[1]\n"
f"{indent}                if len(ret) >= 3: headers = ret[2]\n"
f"{indent}\n"
f"{indent}            data = None\n"
f"{indent}            try:\n"
f"{indent}                if hasattr(resp, 'get_json'):\n"
f"{indent}                    data = resp.get_json(silent=True)\n"
f"{indent}            except Exception:\n"
f"{indent}                data = None\n"
f"{indent}\n"
f"{indent}            if isinstance(data, dict):\n"
f"{indent}                rid = data.get('request_id') or data.get('req_id') or data.get('rid')\n"
f"{indent}                if rid:\n"
f"{indent}                    data['request_id'] = rid\n"
f"{indent}                    data['req_id'] = rid\n"
f"{indent}                    data['rid'] = rid\n"
f"{indent}                if data.get('ok') is None:\n"
f"{indent}                    data['ok'] = True\n"
f"{indent}                new_resp = jsonify(data)\n"
f"{indent}                if headers:\n"
f"{indent}                    try: new_resp.headers.extend(headers)\n"
f"{indent}                    except Exception: pass\n"
f"{indent}                return new_resp if code is None else (new_resp, code)\n"
f"{indent}            return ret\n"
f"{indent}\n"
f"{indent}        app.view_functions[_ep] = _wrapped_run_v1_contract_v4\n"
f"{indent}        try: print('[{marker}] wrapped', _ep)\n"
f"{indent}        except Exception: pass\n"
f"{indent}except Exception as e:\n"
f"{indent}    try: print('[{marker}] failed:', e)\n"
f"{indent}    except Exception: pass\n"
f"{indent}# === END {marker} ===\n\n"
)

txt2 = txt[:ins] + block + txt[ins:]
p.write_text(txt2, encoding="utf-8")
print("[OK] inserted wrapper right before last app.run()")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
