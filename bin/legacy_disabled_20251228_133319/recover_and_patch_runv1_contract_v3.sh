#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "[STEP] 1) Find a compilable vsp_demo_app.py among current + backups..."
mapfile -t CANDS < <(ls -1t "$F" "$F".bak_* 2>/dev/null || true)

GOOD=""
for c in "${CANDS[@]}"; do
  if python3 -m py_compile "$c" >/dev/null 2>&1; then
    GOOD="$c"
    break
  fi
done

if [ -z "$GOOD" ]; then
  echo "[ERR] No compilable candidate found among current+backups."
  echo "[HINT] Try listing backups: ls -1t vsp_demo_app.py.bak_* | head"
  exit 2
fi

if [ "$GOOD" != "$F" ]; then
  cp -f "$GOOD" "$F"
  echo "[RECOVER] Restored $F from $(basename "$GOOD")"
else
  echo "[RECOVER] Current $F is already compilable."
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_before_runv1_contract_v3_${TS}"
echo "[BACKUP] $F.bak_before_runv1_contract_v3_${TS}"

echo "[STEP] 2) Apply append-safe run_v1 contract wrapper..."
python3 - <<'PY'
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

marker = "VSP_RUNV1_CONTRACT_APPENDSAFE_V3"
if marker in txt:
    print("[OK] already patched")
    raise SystemExit(0)

block = (
"\n\n# === VSP_RUNV1_CONTRACT_APPENDSAFE_V3 ===\n"
"def _vsp_install_runv1_contract_appendsafe_v3(app):\n"
"    try:\n"
"        from flask import jsonify\n"
"    except Exception:\n"
"        return\n"
"    try:\n"
"        # Find endpoint by URL rule\n"
"        ep = None\n"
"        try:\n"
"            for r in app.url_map.iter_rules():\n"
"                if getattr(r, 'rule', None) == '/api/vsp/run_v1':\n"
"                    ep = r.endpoint\n"
"                    break\n"
"        except Exception:\n"
"            ep = None\n"
"\n"
"        if not ep:\n"
"            return\n"
"        if ep not in app.view_functions:\n"
"            return\n"
"\n"
"        _orig = app.view_functions[ep]\n"
"\n"
"        def _wrapped(*args, **kwargs):\n"
"            ret = _orig(*args, **kwargs)\n"
"\n"
"            resp, code, headers = ret, None, None\n"
"            if isinstance(ret, tuple) and len(ret) >= 1:\n"
"                resp = ret[0]\n"
"                if len(ret) >= 2:\n"
"                    code = ret[1]\n"
"                if len(ret) >= 3:\n"
"                    headers = ret[2]\n"
"\n"
"            data = None\n"
"            try:\n"
"                if hasattr(resp, 'get_json'):\n"
"                    data = resp.get_json(silent=True)\n"
"            except Exception:\n"
"                data = None\n"
"\n"
"            if isinstance(data, dict):\n"
"                rid = data.get('request_id') or data.get('req_id') or data.get('rid')\n"
"                if rid:\n"
"                    data['request_id'] = rid\n"
"                    data['req_id'] = rid\n"
"                    data['rid'] = rid\n"
"                if data.get('ok') is None:\n"
"                    data['ok'] = True\n"
"\n"
"                new_resp = jsonify(data)\n"
"                if headers:\n"
"                    try:\n"
"                        new_resp.headers.extend(headers)\n"
"                    except Exception:\n"
"                        pass\n"
"                return new_resp if code is None else (new_resp, code)\n"
"\n"
"            return ret\n"
"\n"
"        app.view_functions[ep] = _wrapped\n"
"        try:\n"
"            print('[VSP_RUNV1_CONTRACT_APPENDSAFE_V3] wrapped', ep)\n"
"        except Exception:\n"
"            pass\n"
"    except Exception as e:\n"
"        try:\n"
"            print('[VSP_RUNV1_CONTRACT_APPENDSAFE_V3] failed:', e)\n"
"        except Exception:\n"
"            pass\n"
"\n"
"try:\n"
"    _vsp_install_runv1_contract_appendsafe_v3(app)\n"
"except Exception:\n"
"    pass\n"
"# === END VSP_RUNV1_CONTRACT_APPENDSAFE_V3 ===\n"
)

p.write_text(txt + block, encoding="utf-8")
print("[OK] appended run_v1 contract wrapper v3")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
