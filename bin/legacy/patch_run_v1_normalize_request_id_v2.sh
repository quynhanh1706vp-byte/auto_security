#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_norm_v2_${TS}"
echo "[BACKUP] $F.bak_runv1_norm_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_DEMOAPP_RUNV1_CONTRACT_V1_SAFE" in txt:
    print("[OK] already patched")
    raise SystemExit(0)

block = r'''
# === VSP_DEMOAPP_RUNV1_CONTRACT_V1_SAFE ===
try:
  from flask import jsonify

  # find endpoint by exact rule
  ep = None
  try:
    for r in app.url_map.iter_rules():
      if getattr(r, "rule", None) == "/api/vsp/run_v1":
        ep = r.endpoint
        break
  except Exception:
    ep = None

  if ep and ep in app.view_functions:
    _orig = app.view_functions[ep]

    def _wrapped_run_contract_v1(*args, **kwargs):
      ret = _orig(*args, **kwargs)

      resp, code, headers = ret, None, None
      if isinstance(ret, tuple) and len(ret) >= 1:
        resp = ret[0]
        if len(ret) >= 2: code = ret[1]
        if len(ret) >= 3: headers = ret[2]

      data = None
      try:
        if hasattr(resp, "get_json"):
          data = resp.get_json(silent=True)
      except Exception:
        data = None

      if isinstance(data, dict):
        rid = data.get("request_id") or data.get("req_id") or data.get("rid")
        if rid:
          data["request_id"] = rid
          data["req_id"] = rid
          data["rid"] = rid
        if data.get("ok") is None:
          data["ok"] = True

        new_resp = jsonify(data)
        if headers:
          try: new_resp.headers.extend(headers)
          except Exception: pass
        return new_resp if code is None else (new_resp, code)

      return ret

    app.view_functions[ep] = _wrapped_run_contract_v1
    try: print("[VSP_DEMOAPP_RUNV1_CONTRACT_V1_SAFE] wrapped", ep)
    except Exception: pass

except Exception as e:
  try: print("[VSP_DEMOAPP_RUNV1_CONTRACT_V1_SAFE] failed:", e)
  except Exception: pass
# === END VSP_DEMOAPP_RUNV1_CONTRACT_V1_SAFE ===
'''

# insert near other wrappers if possible, else before __main__, else append
anchor = "VSP_DEMOAPP_STATUS_CONTRACT_V2_SAFE"
i = txt.find(anchor)
if i != -1:
    # insert just after the status contract block end marker if exists
    m = re.search(r"# === END VSP_DEMOAPP_STATUS_CONTRACT_V2_SAFE ===\s*", txt)
    if m:
        ins = m.end()
        txt = txt[:ins] + "\n" + block + "\n" + txt[ins:]
    else:
        txt = txt[:i] + block + "\n" + txt[i:]
else:
    m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', txt, flags=re.M)
    if m:
        ins = m.start()
        txt = txt[:ins] + block + "\n\n" + txt[ins:]
    else:
        txt = txt + "\n\n" + block + "\n"

p.write_text(txt, encoding="utf-8")
print("[OK] patched run_v1 contract wrapper")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
