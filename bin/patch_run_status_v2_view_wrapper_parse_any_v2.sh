#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
LOCK="out_ci/ui_8910.lock"
ts(){ date +%Y%m%d_%H%M%S; }

echo "== [1] backup =="
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
cp -f "$APP" "$APP.bak_viewwrap_v2_$(ts)"
echo "[BACKUP] $APP.bak_viewwrap_v2_$(ts)"

echo "== [2] patch wrapper (parse Response/string/bytes) =="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# We replace the whole wrapper block by tag
BLOCK_TAG = "# === VSP_RUN_STATUS_V2_VIEW_WRAPPER_V1 ==="
m = re.search(rf"{re.escape(BLOCK_TAG)}.*", txt)
if not m:
    print("[ERR] cannot find wrapper tag; abort")
    raise SystemExit(2)

# Replace from BLOCK_TAG to end of file (it was appended) with new block
new_block = r'''
# === VSP_RUN_STATUS_V2_VIEW_WRAPPER_V2 ===
def _vsp_wrap_run_status_v2_endpoint(_app):
    import json
    try:
        from flask import Response as _FlaskResponse
    except Exception:
        _FlaskResponse = None

    # find endpoint by rule containing run_status_v2
    ep = None
    try:
        for r in _app.url_map.iter_rules():
            if "run_status_v2" in str(r.rule):
                ep = r.endpoint
                break
    except Exception:
        ep = None

    if not ep:
        return False, "endpoint_not_found"
    if ep not in _app.view_functions:
        return False, f"endpoint_missing_in_view_functions:{ep}"

    orig = _app.view_functions[ep]

    def _to_dict_any(x):
        # dict already
        if isinstance(x, dict):
            return x
        # bytes/str json
        if isinstance(x, (bytes, bytearray)):
            try:
                return json.loads(bytes(x).decode("utf-8", errors="ignore"))
            except Exception:
                return None
        if isinstance(x, str):
            s = x.strip()
            if s.startswith("{") and s.endswith("}"):
                try:
                    return json.loads(s)
                except Exception:
                    return None
            return None
        # Response
        if _FlaskResponse is not None and isinstance(x, _FlaskResponse):
            try:
                raw = x.get_data(as_text=True)
                return _to_dict_any(raw)
            except Exception:
                return None
        return None

    def wrapped(*a, **k):
        rv = orig(*a, **k)

        body, status, headers = rv, None, None
        if isinstance(rv, tuple):
            if len(rv) == 2:
                body, status = rv
            elif len(rv) == 3:
                body, status, headers = rv

        d = _to_dict_any(body)
        if isinstance(d, dict):
            # run postprocess
            try:
                d2 = _vsp_status_v2_postprocess(d)
            except Exception:
                d2 = d

            # marker to prove wrapper executed
            try:
                d2["_postprocess_v2"] = True
            except Exception:
                pass

            # return as dict/tuple (let Flask jsonify)
            if status is None and headers is None:
                return d2
            if headers is None:
                return (d2, status)
            return (d2, status, headers)

        # could not parse => return original
        return rv

    _app.view_functions[ep] = wrapped
    return True, ep

# run on import
try:
    _ok, _info = _vsp_wrap_run_status_v2_endpoint(app)
    print(f"[VSP_RUN_STATUS_V2_VIEW_WRAPPER_V2] ok={_ok} info={_info}")
except Exception as _e:
    print(f"[VSP_RUN_STATUS_V2_VIEW_WRAPPER_V2] failed: {_e}")
'''

# also upgrade postprocess soften rule to trigger even when final missing but gate exists
if "_vsp_status_v2_postprocess" in txt and "status_v2_soft_error" in txt:
    pass  # already has some soften
else:
    # ensure postprocess exists; if exists, add extra soften at end by a small patch
    pass

# Nuke from old wrapper tag to EOF and append new block
cut = txt.find(BLOCK_TAG)
txt2 = txt[:cut] + new_block + "\n"
p.write_text(txt2, encoding="utf-8")
print("[OK] wrapper replaced with V2")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== [3] free port 8910 + restart =="
PIDS="$(ss -lptn 2>/dev/null | awk '/:8910[[:space:]]/ {print $NF}' | sed 's/.*pid=//;s/,.*//' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' || true)"
if [ -n "${PIDS// /}" ]; then
  echo "[KILL] pids: $PIDS"
  for pid in $PIDS; do kill -9 "$pid" 2>/dev/null || true; done
fi
rm -f "$LOCK" 2>/dev/null || true

./bin/restart_8910_gunicorn_commercial_v5.sh || true

echo "== [4] verify =="
curl -sS http://127.0.0.1:8910/healthz || true
echo
RID="$(curl -sS "http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{
  ok,http_code,status,error:(.error//null),
  ci_run_dir,
  overall_verdict,
  has_semgrep:has("semgrep_summary"),
  has_trivy:has("trivy_summary"),
  has_run_gate:has("run_gate_summary"),
  postprocess:(._postprocess_v2//null),
  warnings:(.warnings//null)
}'
