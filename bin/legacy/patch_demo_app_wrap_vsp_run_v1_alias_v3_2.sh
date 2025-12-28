#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_wrap_alias_v3_2_${TS}"
echo "[BACKUP] $F.bak_wrap_alias_v3_2_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_DEMOAPP_WRAP_ALIAS_RUNV1_V3_2"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Find apply_wrappers_v3 function
m = re.search(r"def _vsp_demoapp_apply_wrappers_v3\s*\(app\)\s*:\s*\n", txt)
if not m:
    raise SystemExit("[ERR] cannot find _vsp_demoapp_apply_wrappers_v3(app)")

# Insert wrapping block for vsp_run_v1_alias right after the existing ep_run wrapping block,
# or if not found, insert near start of function body.
fn_start = m.end()

# heuristic: after line that defines ep_run or after "ep_run ="
insert_pos = None
m_ep = re.search(r"^\s*ep_run\s*=\s*['\"]vsp_run_api_v1\.run_v1['\"]\s*$", txt[fn_start:], flags=re.M)
if m_ep:
    insert_pos = fn_start + m_ep.end()
else:
    insert_pos = fn_start

snippet = r'''

        # === VSP_DEMOAPP_WRAP_ALIAS_RUNV1_V3_2 ===
        ep_alias = "vsp_run_v1_alias"
        if ep_alias in app.view_functions:
            _orig_alias = app.view_functions[ep_alias]
            def _wrapped_alias(*args, **kwargs):
                ret = _orig_alias(*args, **kwargs)
                rid = _vsp_demoapp_extract_reqid_v3(ret)
                if rid:
                    try:
                        payload = request.get_json(silent=True) or {}
                    except Exception:
                        payload = {}
                    _vsp_demoapp_bootstrap_state_v3(rid, payload)
                return ret
            # avoid double wrap
            if not getattr(_orig_alias, "__name__", "").startswith("wrapped_"):
                app.view_functions[ep_alias] = _wrapped_alias
                print("[VSP_DEMOAPP_WRAP_ALIAS_RUNV1_V3_2] wrapped", ep_alias)
        # === END VSP_DEMOAPP_WRAP_ALIAS_RUNV1_V3_2 ===
'''

txt2 = txt[:insert_pos] + snippet + txt[insert_pos:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
