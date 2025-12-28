#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_norm_${TS}"
echo "[BACKUP] $F.bak_runv1_norm_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_RUNV1_NORMALIZE_REQUEST_ID_V1" in txt:
    print("[OK] already patched")
    raise SystemExit(0)

block = r'''
# === VSP_RUNV1_NORMALIZE_REQUEST_ID_V1 ===
try:
  from flask import jsonify
  _target_path = "/api/vsp/run_v1"
  _ep = None
  try:
    for r in app.url_map.iter_rules():
      if getattr(r, "rule", None) == _target_path:
        _ep = r.endpoint
        break
  except Exception:
    _ep = None

  if _ep and _ep in app.view_functions:
    _orig = app.view_functions[_ep]

    def _wrapped_run_v1(*args, **kwargs):
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

    app.view_functions[_ep] = _wrapped_run_v1
    try: print("[VSP_RUNV1_NORMALIZE_REQUEST_ID_V1] wrapped", _ep)
    except Exception: pass

except Exception as e:
  try: print("[VSP_RUNV1_NORMALIZE_REQUEST_ID_V1] failed:", e)
  except Exception: pass
# === END VSP_RUNV1_NORMALIZE_REQUEST_ID_V1 ===
'''

# insert before __main__ if present, else append
m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', txt, flags=re.M)
if m:
    ins = m.start()
    txt = txt[:ins] + block + "\n\n" + txt[ins:]
else:
    txt = txt + "\n\n" + block + "\n"

p.write_text(txt, encoding="utf-8")
print("[OK] patched:", p)
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
