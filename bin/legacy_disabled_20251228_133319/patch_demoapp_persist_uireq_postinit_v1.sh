#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_postinit_v1_${TS}"
echo "[BACKUP] $F.bak_persist_postinit_v1_${TS}"

PY="./.venv/bin/python"
[ -x "$PY" ] || PY="python3"

"$PY" - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace")

# remove old block if exists
txt = re.sub(r"# === VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V1 ===[\s\S]*?# === END VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V1 ===\n?", "", txt, flags=re.M)

block = r"""
# === VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V1 ===
def _vsp_demoapp_persist_uireq_postinit_v1(app):
    try:
        import json as _json, os as _os
        from pathlib import Path as _Path
        # prefer run_api dir if exists, else fallback to ui/out_ci/uireq_v1
        try:
            from run_api import vsp_run_api_v1 as _runapi_mod
            _udir = getattr(_runapi_mod, "_VSP_UIREQ_DIR", None)
        except Exception:
            _udir = None
        if not _udir:
            _udir = _Path(__file__).resolve().parent / "ui" / "out_ci" / "uireq_v1"
        _udir = _Path(str(_udir))
        _udir.mkdir(parents=True, exist_ok=True)

        def _persist(_rid: str, _data: dict) -> bool:
            if not _rid:
                return False
            fp = _udir / f"{_rid}.json"
            cur = {}
            if fp.exists():
                try:
                    cur = _json.loads(fp.read_text(encoding="utf-8", errors="ignore")) or {}
                except Exception:
                    cur = {}
            for k in ["request_id","req_id","ci_run_dir","runner_log","stage_sig","progress_pct",
                      "status","final","killed","kill_reason","stall_timeout_sec","total_timeout_sec"]:
                if k in _data and _data[k] is not None:
                    cur[k] = _data[k]
            tmp = fp.with_suffix(".json.tmp")
            tmp.write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding="utf-8")
            _os.replace(tmp, fp)
            return True

        # wrap all endpoints that serve /api/vsp/run_status_v1/<...>
        endpoints = set()
        for r in app.url_map.iter_rules():
            if r.rule.startswith("/api/vsp/run_status_v1/"):
                endpoints.add(r.endpoint)

        for ep in sorted(endpoints):
            if ep not in app.view_functions:
                continue
            orig = app.view_functions[ep]
            def _make(epname, fn):
                def _wrapped(req_id, *a, **kw):
                    resp = fn(req_id, *a, **kw)
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
                        if _persist(str(rid), data):
                            print(f"[VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V1] persisted {rid}")
                    return resp
                return _wrapped
            app.view_functions[ep] = _make(ep, orig)

        print(f"[VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V1] wrapped endpoints={len(endpoints)} uireq_dir={_udir}")
        return True
    except Exception as _e:
        print("[VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V1] WARN:", _e)
        return False

try:
    # run after app object exists
    _vsp_demoapp_persist_uireq_postinit_v1(app)
except Exception as _e:
    print("[VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V1] WARN(noapp):", _e)
# === END VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V1 ===
"""

# append at end (post-init)
txt = txt.rstrip() + "\n\n" + block + "\n"
p.write_text(txt, encoding="utf-8")
print("[OK] appended postinit persist wrapper")
PY

"$PY" -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
