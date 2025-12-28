#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_watchdog_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_hook_uireq_bootstrap_v3_${TS}"
echo "[BACKUP] $F.bak_hook_uireq_bootstrap_v3_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_watchdog_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_WD_HOOK_UIREQ_BOOTSTRAP_V3"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) Inject helper functions after imports
helper = r'''
# === @@MARK@@ ===
def _vsp_uireq_dir_v3():
    try:
        from pathlib import Path
        try:
            from run_api import vsp_run_api_v1 as m
            d = getattr(m, "_VSP_UIREQ_DIR", None)
            if d:
                return Path(d)
        except Exception:
            pass
        # fallback: .../SECURITY_BUNDLE/ui/run_api/vsp_watchdog_v1.py -> parents[1] = .../SECURITY_BUNDLE/ui
        return Path(__file__).resolve().parents[1] / "ui" / "out_ci" / "uireq_v1"
    except Exception:
        return None

def _vsp_extract_reqid_v3(ret):
    # ret can be: Response | (Response, code) | dict
    try:
        if isinstance(ret, tuple) and ret:
            ret0 = ret[0]
        else:
            ret0 = ret

        if isinstance(ret0, dict):
            rid = ret0.get("request_id") or ret0.get("req_id")
            return str(rid) if rid else ""
        # Flask Response
        j = None
        try:
            j = ret0.get_json(silent=True)
        except Exception:
            j = None
        if isinstance(j, dict):
            rid = j.get("request_id") or j.get("req_id")
            return str(rid) if rid else ""
    except Exception:
        pass
    return ""

def _vsp_bootstrap_statefile_v3(req_id: str, req_payload: dict):
    try:
        import json, time, os
        st_dir = _vsp_uireq_dir_v3()
        if not st_dir:
            return
        st_dir.mkdir(parents=True, exist_ok=True)
        st_path = st_dir / (str(req_id) + ".json")
        if st_path.is_file():
            return
        st = {
            "request_id": str(req_id),
            "synthetic_req_id": True,
            "mode": req_payload.get("mode","") if isinstance(req_payload, dict) else "",
            "profile": req_payload.get("profile","") if isinstance(req_payload, dict) else "",
            "target_type": req_payload.get("target_type","") if isinstance(req_payload, dict) else "",
            "target": req_payload.get("target","") if isinstance(req_payload, dict) else "",
            "ci_run_dir": "",
            "runner_log": "",
            "ci_root_from_pid": None,
            "watchdog_pid": 0,
            "stage_sig": "0/0||0",
            "progress_pct": 0,
            "killed": False,
            "kill_reason": "",
            "final": False,
            "stall_timeout_sec": int(os.environ.get("VSP_STALL_TIMEOUT_SEC","600")),
            "total_timeout_sec": int(os.environ.get("VSP_TOTAL_TIMEOUT_SEC","7200")),
            "state_bootstrap_ts": int(time.time()),
        }
        st_path.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[{@@MARK@@}] wrote {st_path}")
    except Exception as e:
        try:
            print(f"[{@@MARK@@}] FAILED:", e)
        except Exception:
            pass

def _vsp_wrap_viewfunc_v3(fn, endpoint_name: str):
    # Wrap run_v1: after fn() returns => extract req_id => bootstrap file
    # Wrap run_status_v1: before fn(req_id) => ensure file exists
    def _wrapped(*args, **kwargs):
        try:
            # run_status_v1 signature is (req_id)
            if isinstance(endpoint_name, str) and endpoint_name.endswith(".run_status_v1"):
                if args:
                    req_id = str(args[0] or "")
                else:
                    req_id = str(kwargs.get("req_id","") or kwargs.get("request_id","") or "")
                if req_id:
                    try:
                        from flask import request
                        req_payload = request.get_json(silent=True) or {}
                    except Exception:
                        req_payload = {}
                    _vsp_bootstrap_statefile_v3(req_id, req_payload)
        except Exception:
            pass

        ret = fn(*args, **kwargs)

        try:
            if isinstance(endpoint_name, str) and endpoint_name.endswith(".run_v1"):
                rid = _vsp_extract_reqid_v3(ret)
                if rid:
                    try:
                        from flask import request
                        req_payload = request.get_json(silent=True) or {}
                    except Exception:
                        req_payload = {}
                    _vsp_bootstrap_statefile_v3(rid, req_payload)
        except Exception:
            pass
        return ret
    return _wrapped
# === END @@MARK@@ ===
'''.replace("@@MARK@@", MARK)

m_imp = re.search(r"(\n(?:from|import)\s+[^\n]+)+\n", txt, flags=re.M)
if m_imp:
    txt = txt[:m_imp.end()] + helper + "\n" + txt[m_imp.end():]
else:
    txt = helper + "\n" + txt

# 2) Patch installer: any assignment view_functions[endpoint] = <expr>  -> wrap it
# We'll do best-effort replacement for the common pattern used in hook installers.
pat = re.compile(r"(^\s*([A-Za-z_]\w*)\.view_functions\[\s*endpoint\s*\]\s*=\s*)([^\n]+)$", re.M)

def repl(m):
    prefix = m.group(1)
    rhs = m.group(3).rstrip()
    # avoid double-wrapping
    if "_vsp_wrap_viewfunc_v3" in rhs:
        return m.group(0)
    return f"{prefix}_vsp_wrap_viewfunc_v3({rhs}, endpoint)"

txt2, n = pat.subn(repl, txt)
if n == 0:
    raise SystemExit("[ERR] cannot find pattern: <obj>.view_functions[endpoint] = ... (need manual anchor)")

p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK, "wrapped_assignments=", n)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
