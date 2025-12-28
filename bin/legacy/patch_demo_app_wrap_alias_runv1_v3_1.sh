#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_wrap_alias_v3_1_${TS}"
echo "[BACKUP] $F.bak_wrap_alias_v3_1_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_DEMOAPP_WRAP_ALIAS_RUNV1_V3_1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Must have V3 helper functions
need = ["_vsp_demoapp_bootstrap_state_v3", "_vsp_demoapp_extract_reqid_v3"]
for n in need:
    if n not in txt:
        raise SystemExit(f"[ERR] missing {n} in vsp_demo_app.py (V3 helper not present)")

# Replace the body of _vsp_demoapp_apply_wrappers_v3(app) with a safer loop covering alias endpoints
m = re.search(r"def _vsp_demoapp_apply_wrappers_v3\s*\(app\)\s*:\s*\n", txt)
if not m:
    raise SystemExit("[ERR] cannot find def _vsp_demoapp_apply_wrappers_v3(app):")

# find function end (next top-level def)
m_next = re.search(r"^\s*def\s+\w+\s*\(", txt[m.end():], flags=re.M)
end = len(txt) if not m_next else (m.end() + m_next.start())

new_fn = r'''
def _vsp_demoapp_apply_wrappers_v3(app):
    # VSP_DEMOAPP_WRAP_ALIAS_RUNV1_V3_1
    try:
        from flask import request

        # RUN endpoints to cover (route /api/vsp/run_v1 can hit alias)
        run_eps = ["vsp_run_v1_alias", "vsp_run_api_v1.run_v1", "api_vsp_run"]

        for ep in run_eps:
            if ep not in app.view_functions:
                continue
            orig = app.view_functions[ep]

            def _make_wrapped_run(epname, fn):
                def wrapped_run(*args, **kwargs):
                    ret = fn(*args, **kwargs)
                    rid = _vsp_demoapp_extract_reqid_v3(ret)
                    if rid:
                        try:
                            payload = request.get_json(silent=True) or {}
                        except Exception:
                            payload = {}
                        _vsp_demoapp_bootstrap_state_v3(rid, payload)
                    return ret
                wrapped_run.__name__ = "wrapped_run_" + epname.replace(".","_")
                return wrapped_run

            # avoid double wrap
            if getattr(orig, "__name__", "").startswith("wrapped_run_"):
                continue

            app.view_functions[ep] = _make_wrapped_run(ep, orig)
            print("[VSP_DEMOAPP_WRAP_ALIAS_RUNV1_V3_1] wrapped RUN:", ep)

        # STATUS endpoint (canonical)
        st_ep = "vsp_run_api_v1.run_status_v1"
        if st_ep in app.view_functions:
            orig = app.view_functions[st_ep]

            def wrapped_status(req_id, *args, **kwargs):
                try:
                    _vsp_demoapp_bootstrap_state_v3(str(req_id), {})
                except Exception:
                    pass
                return orig(req_id, *args, **kwargs)

            if not getattr(orig, "__name__", "").startswith("wrapped_status_"):
                wrapped_status.__name__ = "wrapped_status_" + st_ep.replace(".","_")
                app.view_functions[st_ep] = wrapped_status
                print("[VSP_DEMOAPP_WRAP_ALIAS_RUNV1_V3_1] wrapped STATUS:", st_ep)

    except Exception as e:
        try:
            print("[VSP_DEMOAPP_WRAP_ALIAS_RUNV1_V3_1] APPLY FAILED:", e)
        except Exception:
            pass
'''

txt2 = txt[:m.start()] + new_fn + "\n# END " + MARK + "\n" + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
