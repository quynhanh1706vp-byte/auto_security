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
cp -f "$WSGI" "${WSGI}.bak_cachehot_v2_${TS}"
echo "[BACKUP] ${WSGI}.bak_cachehot_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_CACHE_HOT_PATHS_V2"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

block = textwrap.dedent(f"""
# ===================== {marker} =====================
# Runtime cache+fallback for hot endpoints using url_map (works with route/add_url_rule/blueprints).
try:
    import time as _time
    from flask import jsonify as _jsonify

    _APP = globals().get("application") or globals().get("app")
    _VSP_P0_CACHE = {{
        "rid_latest_gate_root": {{"ts": 0.0, "data": None}},
        "runs": {{"ts": 0.0, "data": None}},
    }}

    def _vsp_find_endpoint(app, path):
        try:
            for r in app.url_map.iter_rules():
                if str(r.rule) == path:
                    return r.endpoint
        except Exception:
            return None
        return None

    def _vsp_wrap_cached(app, path, cache_key, ttl_sec):
        ep = _vsp_find_endpoint(app, path)
        if not ep:
            print("[VSP] cachehot: endpoint NOT FOUND for", path)
            return False
        if ep not in app.view_functions:
            print("[VSP] cachehot: view_functions missing for", path, "endpoint=", ep)
            return False

        orig = app.view_functions[ep]

        def wrapped(*args, **kwargs):
            now = _time.time()
            c = _VSP_P0_CACHE[cache_key]
            if c.get("data") and (now - c.get("ts", 0.0)) < ttl_sec:
                return _jsonify(c["data"])
            try:
                resp = orig(*args, **kwargs)
                # If resp is 5xx and we have cache -> serve cache
                try:
                    sc = getattr(resp, "status_code", 200)
                    if sc >= 500 and c.get("data"):
                        return _jsonify(c["data"])
                except Exception:
                    pass
                # Try refresh cache from JSON body
                try:
                    data = resp.get_json(silent=True)
                    if isinstance(data, dict):
                        # heuristic: rid endpoint must have rid; runs endpoint must have ok/items
                        ok1 = (cache_key == "rid_latest_gate_root" and data.get("rid"))
                        ok2 = (cache_key == "runs" and data.get("ok") is True and isinstance(data.get("items"), list))
                        if ok1 or ok2:
                            c["ts"] = now
                            c["data"] = data
                except Exception:
                    pass
                return resp
            except Exception:
                if c.get("data"):
                    return _jsonify(c["data"])
                raise

        app.view_functions[ep] = wrapped
        print("[VSP] cachehot enabled:", path, "endpoint=", ep, "ttl=", ttl_sec)
        return True

    if _APP:
        _vsp_wrap_cached(_APP, "/api/vsp/rid_latest_gate_root", "rid_latest_gate_root", 8.0)
        _vsp_wrap_cached(_APP, "/api/vsp/runs", "runs", 3.0)
except Exception as _e:
    print("[VSP] cachehot V2 skipped:", _e)
# ===================== /{marker} =====================
""").lstrip("\n")

p.write_text(s + ("\n" if not s.endswith("\n") else "") + block, encoding="utf-8")
print("[OK] appended:", marker)
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
