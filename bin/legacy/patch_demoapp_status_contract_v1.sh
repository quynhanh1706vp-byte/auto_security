#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_status_contract_v1_${TS}"
echo "[BACKUP] $F.bak_status_contract_v1_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_DEMOAPP_STATUS_CONTRACT_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) add helper function near end (before if __name__ == "__main__": if exists)
helper = r'''
def _vsp_demoapp_status_contract_v1(app):
  # VSP_DEMOAPP_STATUS_CONTRACT_V1
  try:
    from flask import jsonify
    ep = "vsp_run_api_v1.run_status_v1"
    if ep not in app.view_functions:
      return
    orig = app.view_functions[ep]

    def wrapped_status(req_id, *args, **kwargs):
      ret = orig(req_id, *args, **kwargs)

      resp = ret
      code = None
      headers = None
      if isinstance(ret, tuple) and len(ret) >= 1:
        resp = ret[0]
        if len(ret) >= 2:
          code = ret[1]
        if len(ret) >= 3:
          headers = ret[2]

      data = None
      try:
        if hasattr(resp, "get_json"):
          data = resp.get_json(silent=True)
      except Exception:
        data = None

      if isinstance(data, dict):
        # enforce contract fields
        if data.get("ok") is None:
          data["ok"] = True
        if data.get("req_id") is None:
          data["req_id"] = str(req_id)
        if data.get("request_id") is None:
          data["request_id"] = data.get("req_id") or str(req_id)

        new_resp = jsonify(data)
        if headers:
          try:
            new_resp.headers.extend(headers)
          except Exception:
            pass

        if code is None:
          return new_resp
        return new_resp, code

      return ret

    # avoid double wrap
    if not getattr(orig, "__name__", "").startswith("wrapped_status_contract_v1"):
      wrapped_status.__name__ = "wrapped_status_contract_v1"
      app.view_functions[ep] = wrapped_status
      print("[VSP_DEMOAPP_STATUS_CONTRACT_V1] wrapped", ep)
  except Exception as e:
    try:
      print("[VSP_DEMOAPP_STATUS_CONTRACT_V1] failed:", e)
    except Exception:
      pass
'''

m_main = re.search(r"^if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", txt, flags=re.M)
if m_main:
    insert_at = m_main.start()
    txt = txt[:insert_at] + helper + "\n\n" + txt[insert_at:]
else:
    txt = txt + "\n\n" + helper + "\n"

# 2) ensure it's called after _vsp_demoapp_apply_wrappers_v3(app)
# insert call right after first occurrence of _vsp_demoapp_apply_wrappers_v3(app)
call_pat = re.compile(r"(_vsp_demoapp_apply_wrappers_v3\s*\(\s*app\s*\)\s*)", re.M)
if not call_pat.search(txt):
    raise SystemExit("[ERR] cannot find _vsp_demoapp_apply_wrappers_v3(app) call site")

txt = call_pat.sub(r"\1\n  _vsp_demoapp_status_contract_v1(app)  # VSP_DEMOAPP_STATUS_CONTRACT_V1_CALL\n", txt, count=1)

p.write_text(txt, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
