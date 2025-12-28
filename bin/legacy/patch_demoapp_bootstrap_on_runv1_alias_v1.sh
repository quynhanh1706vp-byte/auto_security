#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_bootstrap_alias_${TS}"
echo "[BACKUP] $F.bak_bootstrap_alias_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_DEMOAPP_BOOTSTRAP_ALIAS_RUNV1_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Inject into _vsp_demoapp_apply_wrappers_v3(app) body (safe place)
m = re.search(r"^(\s*)def\s+_vsp_demoapp_apply_wrappers_v3\s*\(\s*app\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def _vsp_demoapp_apply_wrappers_v3(app):")
base = m.group(1)
body = base + "  "
insert_at = m.end()

snippet = f"""
{body}# {MARK}
{body}try:
{body}  import json as _json
{body}  from pathlib import Path as _P
{body}  ep_alias = "vsp_run_v1_alias"
{body}  if ep_alias in app.view_functions:
{body}    _orig_alias = app.view_functions[ep_alias]
{body}    def _wrapped_alias_bootstrap_v1(*args, **kwargs):
{body}      ret = _orig_alias(*args, **kwargs)
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
{body}      # bootstrap uireq state file from run_v1 JSON response
{body}      try:
{body}        if isinstance(data, dict) and data.get("request_id"):
{body}          rid = str(data.get("request_id"))
{body}          udir = _P(__file__).resolve().parent / "ui" / "out_ci" / "uireq_v1"
{body}          udir.mkdir(parents=True, exist_ok=True)
{body}          f = udir / f"{{rid}}.json"
{body}          state = {{
{body}            "request_id": rid,
{body}            "req_id": rid,
{body}            "ok": True,
{body}            "synthetic_req_id": True,
{body}            "mode": data.get("ci_mode") or data.get("mode") or "LOCAL_UI",
{body}            "profile": data.get("profile") or "",
{body}            "target": data.get("target") or "",
{body}            "target_type": data.get("target_type") or "path",
{body}            "stage_sig": "0/0||0",
{body}            "final": False,
{body}            "killed": False,
{body}          }}
{body}          f.write_text(_json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
{body}          try: f.chmod(0o755)
{body}          except Exception: pass
{body}          print("[{MARK}] wrote", str(f))
{body}      except Exception as e:
{body}        try: print("[{MARK}] write failed:", e)
{body}        except Exception: pass
{body}      return ret
{body}    app.view_functions[ep_alias] = _wrapped_alias_bootstrap_v1
{body}    print("[{MARK}] wrapped", ep_alias)
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
