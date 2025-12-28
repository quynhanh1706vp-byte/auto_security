#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_uireq_on_status_v1_${TS}"
echo "[BACKUP] $F.bak_persist_uireq_on_status_v1_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_DEMOAPP_PERSIST_UIREQ_ON_STATUS_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r'''
# === {MARK} ===
def _vsp_demoapp_install_persist_uireq_on_status_v1(app):
  try:
    if getattr(app, "_vsp_persist_uireq_on_status_v1_installed", False):
      return
    app._vsp_persist_uireq_on_status_v1_installed = True

    ep = "vsp_run_api_v1.run_status_v1"
    orig = app.view_functions.get(ep)
    if not orig:
      print("[{MARK}] WARN: endpoint not found:", ep)
      return

    def _persist(req_id, patch):
      try:
        from run_api import vsp_run_api_v1 as api
        udir = getattr(api, "_VSP_UIREQ_DIR", None)
        if not udir or not req_id:
          return False
        sp = Path(str(udir)) / f"{req_id}.json"
        if not sp.exists():
          return False
        import json
        st = json.loads(sp.read_text(encoding="utf-8", errors="replace") or "{}")
        changed = False
        for k,v in (patch or {}).items():
          if v is None:
            continue
          if st.get(k) != v:
            st[k] = v
            changed = True
        if changed:
          sp.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
        return changed
      except Exception as e:
        print("[{MARK}] persist WARN:", e)
        return False

    def wrapped(*args, **kwargs):
      resp = orig(*args, **kwargs)

      # normalize resp -> dict + status
      data = None
      code = None
      try:
        if isinstance(resp, tuple) and len(resp) >= 1:
          data = resp[0]
          code = resp[1] if len(resp) >= 2 else None
        else:
          data = resp
      except Exception:
        data = None

      # Response object -> dict
      d = None
      try:
        if hasattr(data, "get_json"):
          d = data.get_json(silent=True)
        elif isinstance(data, dict):
          d = data
      except Exception:
        d = None

      try:
        if isinstance(d, dict) and d.get("ok") is True:
          rid = d.get("req_id") or d.get("request_id")
          patch = {
            "ci_run_dir": d.get("ci_run_dir"),
            "runner_log": d.get("runner_log"),
            "stage_sig": d.get("stage_sig"),
            "progress_pct": d.get("progress_pct"),
            "final": d.get("final"),
            "killed": d.get("killed"),
            "kill_reason": d.get("kill_reason"),
          }
          if _persist(rid, patch):
            print("[{MARK}] persisted", rid)
      except Exception as e:
        print("[{MARK}] WARN:", e)

      return resp

    app.view_functions[ep] = wrapped
    print("[{MARK}] wrapped", ep)
  except Exception as e:
    print("[{MARK}] FATAL:", e)
# === END {MARK} ===
'''.replace("{MARK}", MARK)

# insert before if __name__ == "__main__"
m = re.search(r"\nif\s+__name__\s*==\s*['\"]__main__['\"]\s*:\s*\n", txt)
if m:
    ins = "\n" + block + "\n# install persist hook\ntry:\n  _vsp_demoapp_install_persist_uireq_on_status_v1(app)\nexcept Exception as _e:\n  print('[%s] install failed:' % '%s', _e)\n\n" % (MARK, MARK)
    txt = txt[:m.start()] + ins + txt[m.start():]
else:
    # fallback append
    txt = txt + "\n" + block + "\ntry:\n  _vsp_demoapp_install_persist_uireq_on_status_v1(app)\nexcept Exception as _e:\n  print('[%s] install failed:' % '%s', _e)\n" % (MARK, MARK)

p.write_text(txt, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
