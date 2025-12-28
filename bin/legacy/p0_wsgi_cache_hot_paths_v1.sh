#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_cachehot_${TS}"
echo "[BACKUP] ${WSGI}.bak_cachehot_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P0_CACHE_HOT_PATHS_V1"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

def find_endpoint(path: str):
    # add_url_rule('/api/vsp/xxx', 'endpoint_name', func, ...)
    m = re.search(r"add_url_rule\(\s*['\"]" + re.escape(path) + r"['\"]\s*,\s*['\"]([^'\"]+)['\"]", s)
    return m.group(1) if m else None

ep_rid = find_endpoint("/api/vsp/rid_latest_gate_root")
ep_runs = find_endpoint("/api/vsp/runs")

if not ep_rid:
    # fallback: endpoint often equals function name; try find any add_url_rule containing rid_latest_gate_root
    m = re.search(r"add_url_rule\(\s*['\"][^'\"]*rid_latest_gate_root[^'\"]*['\"]\s*,\s*['\"]([^'\"]+)['\"]", s)
    ep_rid = m.group(1) if m else None

if not ep_runs:
    m = re.search(r"add_url_rule\(\s*['\"][^'\"]*/api/vsp/runs['\"]\s*,\s*['\"]([^'\"]+)['\"]", s)
    ep_runs = m.group(1) if m else None

if not ep_rid and not ep_runs:
    raise SystemExit("[ERR] cannot locate endpoints for cache patch")

block = textwrap.dedent(f"""
# ===================== {marker} =====================
# Cache + fallback for hot endpoints to avoid UI skeleton / random FAIL.
try:
    import time as _time
    from flask import jsonify as _jsonify

    _VSP_P0_CACHE = {{
        "rid": {{"ts": 0.0, "data": None}},
        "runs": {{"ts": 0.0, "data": None}},
    }}

    _APP = globals().get("application") or globals().get("app")
    if _APP:
        # 1) rid_latest_gate_root: cache 5s, fallback to last-good on error
        _EP_RID = {repr(ep_rid) if ep_rid else "None"}
        if _EP_RID and _EP_RID in _APP.view_functions:
            _orig_rid = _APP.view_functions[_EP_RID]
            def _vsp_cached_rid(*args, **kwargs):
                now = _time.time()
                c = _VSP_P0_CACHE["rid"]
                if c.get("data") and (now - c.get("ts", 0.0)) < 5.0:
                    return _jsonify(c["data"])
                try:
                    resp = _orig_rid(*args, **kwargs)
                    # if server returns 5xx but we have cache -> serve cache
                    try:
                        sc = getattr(resp, "status_code", 200)
                        if sc >= 500 and c.get("data"):
                            return _jsonify(c["data"])
                    except Exception:
                        pass
                    try:
                        data = resp.get_json(silent=True)
                        if isinstance(data, dict) and data.get("rid"):
                            c["ts"] = now
                            c["data"] = data
                    except Exception:
                        pass
                    return resp
                except Exception:
                    if c.get("data"):
                        return _jsonify(c["data"])
                    raise
            _APP.view_functions[_EP_RID] = _vsp_cached_rid
            print("[VSP] cachehot rid_latest_gate_root enabled; endpoint=", _EP_RID)

        # 2) runs: cache 2s (UI hay gọi lặp), fallback last-good on error
        _EP_RUNS = {repr(ep_runs) if ep_runs else "None"}
        if _EP_RUNS and _EP_RUNS in _APP.view_functions:
            _orig_runs = _APP.view_functions[_EP_RUNS]
            def _vsp_cached_runs(*args, **kwargs):
                now = _time.time()
                c = _VSP_P0_CACHE["runs"]
                if c.get("data") and (now - c.get("ts", 0.0)) < 2.0:
                    return _jsonify(c["data"])
                try:
                    resp = _orig_runs(*args, **kwargs)
                    try:
                        sc = getattr(resp, "status_code", 200)
                        if sc >= 500 and c.get("data"):
                            return _jsonify(c["data"])
                    except Exception:
                        pass
                    try:
                        data = resp.get_json(silent=True)
                        if isinstance(data, dict) and data.get("ok") is True:
                            c["ts"] = now
                            c["data"] = data
                    except Exception:
                        pass
                    return resp
                except Exception:
                    if c.get("data"):
                        return _jsonify(c["data"])
                    raise
            _APP.view_functions[_EP_RUNS] = _vsp_cached_runs
            print("[VSP] cachehot runs enabled; endpoint=", _EP_RUNS)

except Exception as _e:
    print("[VSP] cachehot patch skipped:", _e)
# ===================== /{marker} =====================
""").lstrip("\n")

p.write_text(s + ("\n" if not s.endswith("\n") else "") + block, encoding="utf-8")
print("[OK] appended:", marker)
print("[DBG] ep_rid=", ep_rid, "ep_runs=", ep_runs)
PY

echo "== py_compile =="
python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" || true
sleep 1

echo "== smoke timing =="
echo "-- rid_latest_gate_root x3 --"
for i in 1 2 3; do
  curl -sS -o /dev/null -w "i=$i status=%{http_code} t=%{time_total}\n" "$BASE/api/vsp/rid_latest_gate_root" || true
done
echo "-- runs?limit=30 x2 --"
for i in 1 2; do
  curl -sS -o /dev/null -w "i=$i status=%{http_code} t=%{time_total}\n" "$BASE/api/vsp/runs?limit=30" || true
done

echo "[DONE] Hard reload: Ctrl+Shift+R on $BASE/vsp5"
