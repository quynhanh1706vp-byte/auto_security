#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_from_status_v2_${TS}"
echo "[BACKUP] $F.bak_persist_from_status_v2_${TS}"

PY="./.venv/bin/python"
[ -x "$PY" ] || PY="python3"

"$PY" - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace")

block_re = re.compile(r"# === VSP_DEMOAPP_PERSIST_UIREQ_FROM_STATUS_V2 ===[\s\S]*?# === END VSP_DEMOAPP_PERSIST_UIREQ_FROM_STATUS_V2 ===\n", re.M)
txt = block_re.sub("", txt)

block = r"""
# === VSP_DEMOAPP_PERSIST_UIREQ_FROM_STATUS_V2 ===
try:
    from run_api import vsp_run_api_v1 as _runapi_mod
    import json as _json, os as _os
    from pathlib import Path as _Path

    def _vsp_persist_uireq(_rid: str, _data: dict) -> bool:
        udir = getattr(_runapi_mod, "_VSP_UIREQ_DIR", None)
        if not udir or not _rid:
            return False
        fp = _Path(str(udir)) / f"{_rid}.json"
        cur = {}
        if fp.exists():
            try:
                cur = _json.loads(fp.read_text(encoding="utf-8", errors="ignore")) or {}
            except Exception:
                cur = {}

        # merge fields from status response
        for k in [
            "request_id","req_id",
            "ci_run_dir","runner_log",
            "stage_sig","progress_pct",
            "status","final",
            "killed","kill_reason",
            "stall_timeout_sec","total_timeout_sec",
        ]:
            if k in _data and _data[k] is not None:
                cur[k] = _data[k]

        tmp = fp.with_suffix(".json.tmp")
        tmp.write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding="utf-8")
        _os.replace(tmp, fp)
        return True

    def _wrap_status_persist(app, endpoint="vsp_run_api_v1.run_status_v1"):
        if not app or endpoint not in getattr(app, "view_functions", {}):
            return False
        _orig = app.view_functions[endpoint]

        def _wrapped(req_id, *a, **kw):
            resp = _orig(req_id, *a, **kw)

            body = resp[0] if isinstance(resp, tuple) else resp
            data = None
            try:
                if hasattr(body, "get_json"):
                    data = body.get_json(silent=True)
                elif isinstance(body, dict):
                    data = body
            except Exception:
                data = None

            if isinstance(data, dict):
                rid = data.get("request_id") or data.get("req_id") or req_id
                if rid and _vsp_persist_uireq(rid, data):
                    print(f"[VSP_DEMOAPP_PERSIST_UIREQ_FROM_STATUS_V2] persisted {rid}")
            return resp

        app.view_functions[endpoint] = _wrapped
        print(f"[VSP_DEMOAPP_PERSIST_UIREQ_FROM_STATUS_V2] wrapped {endpoint}")
        return True

    _wrap_status_persist(app)
except Exception as _e:
    print("[VSP_DEMOAPP_PERSIST_UIREQ_FROM_STATUS_V2] WARN:", _e)
# === END VSP_DEMOAPP_PERSIST_UIREQ_FROM_STATUS_V2 ===
"""

# insert before if __name__ == "__main__" if exists, else append
m = re.search(r"^if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", txt, flags=re.M)
if m:
    ins = m.start()
    txt = txt[:ins] + block + "\n" + txt[ins:]
else:
    txt = txt + "\n" + block + "\n"

p.write_text(txt, encoding="utf-8")
print("[OK] injected VSP_DEMOAPP_PERSIST_UIREQ_FROM_STATUS_V2")
PY

"$PY" -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
