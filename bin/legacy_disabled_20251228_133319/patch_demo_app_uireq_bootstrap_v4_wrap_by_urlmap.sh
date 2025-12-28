#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_uireq_wrap_urlmap_v4_${TS}"
echo "[BACKUP] $F.bak_uireq_wrap_urlmap_v4_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_DEMOAPP_UIREQ_BOOTSTRAP_WRAP_URLMAP_V4"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) ensure V3 helper exists
if "_vsp_demoapp_bootstrap_state_v3" not in txt:
    raise SystemExit("[ERR] missing _vsp_demoapp_bootstrap_state_v3; apply V3 helper patch first.")

# 2) add V4 apply function right after V3 apply function (or after helper block)
insert_anchor = re.search(r"def _vsp_demoapp_apply_wrappers_v3\s*\(app\)\s*:\s*\n", txt)
if not insert_anchor:
    raise SystemExit("[ERR] cannot find def _vsp_demoapp_apply_wrappers_v3(app):")

# find end of v3 function by next top-level def
start = insert_anchor.start()
m_next = re.search(r"^\s*def\s+_vsp_demoapp_\w+\s*\(", txt[insert_anchor.end():], flags=re.M)
end = len(txt) if not m_next else (insert_anchor.end() + m_next.start())

# Build V4 function (uses url_map to locate endpoints)
v4 = r'''
def _vsp_demoapp_apply_wrappers_v4(app):
    """
    Robust wrapper installer:
      - Discover endpoints serving /api/vsp/run_v1 and /api/vsp/run_status_v1/<...> from app.url_map
      - Wrap those endpoints (NOT only vsp_run_api_v1.run_v1)
    """
    try:
        from flask import request

        run_eps = set()
        st_eps  = set()
        try:
            for rule in app.url_map.iter_rules():
                r = getattr(rule, "rule", "") or ""
                ep = getattr(rule, "endpoint", "") or ""
                methods = set(getattr(rule, "methods", []) or [])
                if r == "/api/vsp/run_v1" and ("POST" in methods or not methods):
                    run_eps.add(ep)
                if r.startswith("/api/vsp/run_status_v1/"):
                    st_eps.add(ep)
        except Exception as e:
            print("[VSP_DEMOAPP_UIREQ_BOOTSTRAP_SAFE_V4] url_map scan failed:", e)

        # Fallback known endpoints if url_map scan returns empty
        if not run_eps:
            for ep in ("api_vsp_run","vsp_run_v1_alias","vsp_run_api_v1.run_v1"):
                if ep in app.view_functions:
                    run_eps.add(ep)
        if not st_eps:
            for ep in ("api_vsp_run_status","vsp_run_api_v1.run_status_v1"):
                if ep in app.view_functions:
                    st_eps.add(ep)

        # Wrap run endpoints
        for ep in sorted(run_eps):
            if ep not in app.view_functions:
                continue
            orig = app.view_functions[ep]
            # avoid double wrap
            if getattr(orig, "__name__", "").startswith("wrapped_run_v4_"):
                continue

            def _make_wrapped_run(epname, fn):
                def wrapped_run_v4_(*args, **kwargs):
                    ret = fn(*args, **kwargs)
                    rid = _vsp_demoapp_extract_reqid_v3(ret)
                    if rid:
                        try:
                            payload = request.get_json(silent=True) or {}
                        except Exception:
                            payload = {}
                        _vsp_demoapp_bootstrap_state_v3(rid, payload)
                    return ret
                wrapped_run_v4_.__name__ = "wrapped_run_v4_" + epname.replace(".","_")
                return wrapped_run_v4_

            app.view_functions[ep] = _make_wrapped_run(ep, orig)
            print("[VSP_DEMOAPP_UIREQ_BOOTSTRAP_SAFE_V4] wrapped RUN endpoint:", ep)

        # Wrap status endpoints
        for ep in sorted(st_eps):
            if ep not in app.view_functions:
                continue
            orig = app.view_functions[ep]
            if getattr(orig, "__name__", "").startswith("wrapped_status_v4_"):
                continue

            def _make_wrapped_status(epname, fn):
                def wrapped_status_v4_(*args, **kwargs):
                    # try extract req_id from kwargs or first arg
                    req_id = ""
                    if kwargs:
                        req_id = str(kwargs.get("req_id") or kwargs.get("request_id") or "")
                    if not req_id and args:
                        req_id = str(args[0] or "")
                    if req_id:
                        _vsp_demoapp_bootstrap_state_v3(req_id, {})
                    return fn(*args, **kwargs)
                wrapped_status_v4_.__name__ = "wrapped_status_v4_" + epname.replace(".","_")
                return wrapped_status_v4_

            app.view_functions[ep] = _make_wrapped_status(ep, orig)
            print("[VSP_DEMOAPP_UIREQ_BOOTSTRAP_SAFE_V4] wrapped STATUS endpoint:", ep)

    except Exception as e:
        try:
            print("[VSP_DEMOAPP_UIREQ_BOOTSTRAP_SAFE_V4] APPLY FAILED:", e)
        except Exception:
            pass
'''

# Insert V4 just after v3 function body
txt2 = txt[:end] + "\n# " + MARK + "\n" + v4 + "\n# END " + MARK + "\n" + txt[end:]

# 3) Replace any call to _vsp_demoapp_apply_wrappers_v3(app) with v4
txt2, nrep = re.subn(r"_vsp_demoapp_apply_wrappers_v3\s*\(\s*app\s*\)",
                     "_vsp_demoapp_apply_wrappers_v4(app)", txt2)
print("[OK] replaced apply calls:", nrep)

p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
