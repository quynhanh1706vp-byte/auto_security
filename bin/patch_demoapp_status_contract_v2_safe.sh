#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_status_contract_v2_${TS}"
echo "[BACKUP] $F.bak_status_contract_v2_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_DEMOAPP_STATUS_CONTRACT_V2_SAFE"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# chèn block wrapper vào TRONG thân hàm _vsp_demoapp_apply_wrappers_v3(app)
m = re.search(r"^(\s*)def\s+_vsp_demoapp_apply_wrappers_v3\s*\(\s*app\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def _vsp_demoapp_apply_wrappers_v3(app):")

base = m.group(1)
body = base + "  "

insert_at = m.end()

snippet = f"""
{body}# {MARK}
{body}try:
{body}  from flask import jsonify
{body}  ep = "vsp_run_api_v1.run_status_v1"
{body}  if ep in app.view_functions:
{body}    _orig = app.view_functions[ep]
{body}    def _wrapped_status_contract_v2(req_id, *args, **kwargs):
{body}      ret = _orig(req_id, *args, **kwargs)
{body}      resp, code, headers = ret, None, None
{body}      if isinstance(ret, tuple) and len(ret) >= 1:
{body}        resp = ret[0]
{body}        if len(ret) >= 2: code = ret[1]
{body}        if len(ret) >= 3: headers = ret[2]
{body}      data = None
{body}      try:
{body}        if hasattr(resp, "get_json"):
{body}          data = resp.get_json(silent=True)
{body}      except Exception:
{body}        data = None
{body}      if isinstance(data, dict):
{body}        if data.get("ok") is None: data["ok"] = True
{body}        if data.get("req_id") is None: data["req_id"] = str(req_id)
{body}        if data.get("request_id") is None: data["request_id"] = data.get("req_id") or str(req_id)
{body}        new_resp = jsonify(data)
{body}        if headers:
{body}          try: new_resp.headers.extend(headers)
{body}          except Exception: pass
{body}        return new_resp if code is None else (new_resp, code)
{body}      return ret
{body}    app.view_functions[ep] = _wrapped_status_contract_v2
{body}    print("[{MARK}] wrapped", ep)
{body}except Exception as e:
{body}  try: print("[{MARK}] failed:", e)
{body}  except Exception: pass
{body}# END {MARK}
"""

txt2 = txt[:insert_at] + snippet + txt[insert_at:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
