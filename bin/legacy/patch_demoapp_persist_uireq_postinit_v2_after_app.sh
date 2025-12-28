#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_postinit_v2_${TS}"
echo "[BACKUP] $F.bak_persist_postinit_v2_${TS}"

PY="./.venv/bin/python"
[ -x "$PY" ] || PY="python3"

"$PY" - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace")

# remove old block(s) if any
txt = re.sub(r"# === VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V\d+[\s\S]*?# === END VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V\d+ ===\n?", "", txt, flags=re.M)

block = r"""
# === VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V2 ===
def _vsp_demoapp_persist_uireq_postinit_v2(app):
    try:
        import json as _json, os as _os
        from pathlib import Path as _Path

        # decide uireq dir
        _udir = None
        try:
            from run_api import vsp_run_api_v1 as _m
            _udir = getattr(_m, "_VSP_UIREQ_DIR", None)
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

        # find endpoints serving run_status
        endpoints = set()
        for r in app.url_map.iter_rules():
            if r.rule.startswith("/api/vsp/run_status_v1/"):
                endpoints.add(r.endpoint)

        wrapped = 0
        for ep in sorted(endpoints):
            if ep not in app.view_functions:
                continue
            orig = app.view_functions[ep]

            def _make(_ep, _fn):
                def _wrapped(req_id, *a, **kw):
                    resp = _fn(req_id, *a, **kw)
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
                            print(f"[VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V2] persisted {rid}")
                    return resp
                return _wrapped

            app.view_functions[ep] = _make(ep, orig)
            wrapped += 1

        print(f"[VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V2] wrapped={wrapped} uireq_dir={_udir}")
        return True
    except Exception as _e:
        print("[VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V2] WARN:", _e)
        return False
# === END VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V2 ===
"""

# insert block near top (after imports) if possible
if "VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V2" not in txt:
    txt = txt.rstrip() + "\n\n" + block + "\n"

# now inject CALL right after app is created
def inject_after(patterns, call_line):
    global txt
    for pat in patterns:
        m = re.search(pat, txt, flags=re.M)
        if m:
            ins = m.end()
            # insert on next line
            txt = txt[:ins] + "\n" + call_line + txt[ins:]
            return True
    return False

call = "try:\n    _vsp_demoapp_persist_uireq_postinit_v2(app)\nexcept Exception as _e:\n    print('[VSP_DEMOAPP_PERSIST_UIREQ_POSTINIT_V2] WARN(noapp):', _e)\n"

# only inject once
if "WARN(noapp)" not in txt and "_vsp_demoapp_persist_uireq_postinit_v2(app)" not in txt:
    ok = inject_after(
        patterns=[
            r"^app\s*=\s*Flask\([^\n]*\)\s*$",
            r"^app\s*=\s*flask\.Flask\([^\n]*\)\s*$",
            r"^app\s*=\s*create_app\(\)\s*$",
            r"^app\s*=\s*create_app\([^\n]*\)\s*$",
        ],
        call_line=call
    )
    if not ok:
        # fallback: inject before app.run if exists
        m = re.search(r"^\s*app\.run\(", txt, flags=re.M)
        if m:
            txt = txt[:m.start()] + call + "\n" + txt[m.start():]
            ok = True
    if not ok:
        raise SystemExit("[ERR] cannot find where app is created (no 'app = Flask(...)' / 'app = create_app()' / 'app.run(')")

p.write_text(txt, encoding="utf-8")
print("[OK] patched V2 (after app creation hook)")
PY

"$PY" -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
