#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_bootstrap_helper_v7_${TS}"
echo "[BACKUP] $F.bak_bootstrap_helper_v7_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_RUN_V1_STATEFILE_BOOTSTRAP_V6_WRAP_RETURNS"

# replace ONLY the helper function body inside the MARK block
pat = r"(# === " + re.escape(MARK) + r" ===\s*\n)([\s\S]*?)(# === END " + re.escape(MARK) + r" ===\s*\n)"
m = re.search(pat, txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find V6 MARK block to patch helper")

new_helper = f"""# === {MARK} ===
def _vsp_bootstrap_statefile_v6(req_id: str, req_payload: dict):
    try:
        from pathlib import Path
        import json, time, os

        # IMPORTANT: write to the SAME dir that run_status_v1 reads from (_VSP_UIREQ_DIR) if present
        st_dir = None
        try:
            st_dir = globals().get("_VSP_UIREQ_DIR", None)
        except Exception:
            st_dir = None

        if st_dir:
            st_dir = Path(st_dir)
        else:
            ui_root = Path(__file__).resolve().parents[1]   # .../SECURITY_BUNDLE/ui
            st_dir = ui_root / "out_ci" / "ui_req_state"

        st_dir.mkdir(parents=True, exist_ok=True)
        st_path = st_dir / (str(req_id) + ".json")

        state0 = {{}}
        if st_path.is_file():
            try:
                state0 = json.loads(st_path.read_text(encoding="utf-8", errors="ignore") or "{{}}")
                if not isinstance(state0, dict):
                    state0 = {{}}
            except Exception:
                state0 = {{}}

        state0.setdefault("request_id", str(req_id))
        state0.setdefault("synthetic_req_id", True)

        for k in ("mode","profile","target_type","target"):
            if (not state0.get(k)) and (req_payload.get(k) is not None):
                state0[k] = req_payload.get(k) or ""

        state0.setdefault("ci_run_dir", "")
        state0.setdefault("runner_log", "")
        state0.setdefault("ci_root_from_pid", None)
        state0.setdefault("watchdog_pid", 0)
        state0.setdefault("stage_sig", "0/0||0")
        state0.setdefault("progress_pct", 0)
        state0.setdefault("killed", False)
        state0.setdefault("kill_reason", "")
        state0.setdefault("final", False)

        state0.setdefault("stall_timeout_sec", int(os.environ.get("VSP_STALL_TIMEOUT_SEC","600")))
        state0.setdefault("total_timeout_sec", int(os.environ.get("VSP_TOTAL_TIMEOUT_SEC","7200")))

        state0["state_bootstrap_ts"] = int(time.time())

        rp = state0.get("req_payload")
        if not isinstance(rp, dict):
            rp = {{}}
        for k in ("mode","profile","target_type","target"):
            if k in req_payload:
                rp[k] = req_payload.get(k)
        state0["req_payload"] = rp

        st_path.write_text(json.dumps(state0, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[BOOTSTRAP_V7] wrote state: {{st_path}}")
    except Exception as e:
        try:
            print("[BOOTSTRAP_V7] FAILED:", e)
        except Exception:
            pass
        return
# === END {MARK} ===
"""

txt2 = txt[:m.start()] + new_helper + txt[m.end():]
p.write_text(txt2, encoding="utf-8")
print("[OK] helper upgraded to V7 (use _VSP_UIREQ_DIR + debug prints)")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
