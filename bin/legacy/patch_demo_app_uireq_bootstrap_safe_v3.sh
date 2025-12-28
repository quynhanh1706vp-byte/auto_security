#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_uireq_safe_v3_${TS}"
echo "[BACKUP] $F.bak_uireq_safe_v3_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_DEMOAPP_UIREQ_BOOTSTRAP_SAFE_V3"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) Inject helper block after imports
helper = r'''
# === VSP_DEMOAPP_UIREQ_BOOTSTRAP_SAFE_V3 ===
def _vsp_demoapp_uireq_dir_v3():
    try:
        from pathlib import Path
        try:
            from run_api import vsp_run_api_v1 as m
            d = getattr(m, "_VSP_UIREQ_DIR", None)
            if d:
                return Path(d)
        except Exception:
            pass
        return Path(__file__).resolve().parent / "ui" / "out_ci" / "uireq_v1"
    except Exception:
        return None

def _vsp_demoapp_extract_reqid_v3(ret):
    try:
        if isinstance(ret, tuple) and ret:
            ret0 = ret[0]
        else:
            ret0 = ret
        if isinstance(ret0, dict):
            rid = ret0.get("request_id") or ret0.get("req_id")
            return str(rid) if rid else ""
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

def _vsp_demoapp_bootstrap_state_v3(req_id: str, req_payload: dict):
    try:
        import json, time, os
        from pathlib import Path
        st_dir = _vsp_demoapp_uireq_dir_v3()
        if not st_dir:
            return
        st_dir.mkdir(parents=True, exist_ok=True)
        st_path = st_dir / (str(req_id) + ".json")
        if st_path.is_file():
            return
        st = {
            "request_id": str(req_id),
            "synthetic_req_id": True,
            "mode": (req_payload.get("mode","") if isinstance(req_payload, dict) else ""),
            "profile": (req_payload.get("profile","") if isinstance(req_payload, dict) else ""),
            "target_type": (req_payload.get("target_type","") if isinstance(req_payload, dict) else ""),
            "target": (req_payload.get("target","") if isinstance(req_payload, dict) else ""),
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
        print("[VSP_DEMOAPP_UIREQ_BOOTSTRAP_SAFE_V3] wrote", st_path)
    except Exception as e:
        try:
            print("[VSP_DEMOAPP_UIREQ_BOOTSTRAP_SAFE_V3] FAILED:", e)
        except Exception:
            pass

def _vsp_demoapp_apply_wrappers_v3(app):
    try:
        from flask import request
        ep_run = "vsp_run_api_v1.run_v1"
        ep_st  = "vsp_run_api_v1.run_status_v1"

        if ep_run in app.view_functions:
            orig = app.view_functions[ep_run]
            def wrapped_run(*args, **kwargs):
                ret = orig(*args, **kwargs)
                rid = _vsp_demoapp_extract_reqid_v3(ret)
                if rid:
                    try:
                        payload = request.get_json(silent=True) or {}
                    except Exception:
                        payload = {}
                    _vsp_demoapp_bootstrap_state_v3(rid, payload)
                return ret
            app.view_functions[ep_run] = wrapped_run
            print("[VSP_DEMOAPP_UIREQ_BOOTSTRAP_SAFE_V3] wrapped", ep_run)

        if ep_st in app.view_functions:
            orig = app.view_functions[ep_st]
            def wrapped_status(req_id, *args, **kwargs):
                try:
                    _vsp_demoapp_bootstrap_state_v3(str(req_id), {})
                except Exception:
                    pass
                return orig(req_id, *args, **kwargs)
            app.view_functions[ep_st] = wrapped_status
            print("[VSP_DEMOAPP_UIREQ_BOOTSTRAP_SAFE_V3] wrapped", ep_st)

    except Exception as e:
        try:
            print("[VSP_DEMOAPP_UIREQ_BOOTSTRAP_SAFE_V3] APPLY FAILED:", e)
        except Exception:
            pass
# === END VSP_DEMOAPP_UIREQ_BOOTSTRAP_SAFE_V3 ===
'''

m_imp = re.search(r"(\n(?:from|import)\s+[^\n]+)+\n", txt, flags=re.M)
if m_imp:
    txt = txt[:m_imp.end()] + helper + "\n" + txt[m_imp.end():]
else:
    txt = helper + "\n" + txt

# 2) Insert apply call right BEFORE app.run(...) at same indentation level
m_run = re.search(r"^(?P<ind>\s*)app\.run\s*\(", txt, flags=re.M)
if m_run:
    ind = m_run.group("ind")
    apply = f"{ind}# {MARK} APPLY\n{ind}try:\n{ind}  _vsp_demoapp_apply_wrappers_v3(app)\n{ind}except Exception:\n{ind}  pass\n{ind}# END {MARK} APPLY\n\n"
    txt = txt[:m_run.start()] + apply + txt[m_run.start():]
else:
    # fallback: inside __main__
    m_main = re.search(r'^(?P<ind>\s*)if\s+__name__\s*==\s*["\']__main__["\']\s*:\s*$', txt, flags=re.M)
    if not m_main:
        raise SystemExit("[ERR] cannot find app.run(...) nor __main__ block")
    ind = m_main.group("ind") + "  "
    apply = f"\n{m_main.group('ind')}# {MARK} APPLY\n{ind}try:\n{ind}  _vsp_demoapp_apply_wrappers_v3(app)\n{ind}except Exception:\n{ind}  pass\n{m_main.group('ind')}# END {MARK} APPLY\n"
    txt = txt[:m_main.end()] + apply + txt[m_main.end():]

p.write_text(txt, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
