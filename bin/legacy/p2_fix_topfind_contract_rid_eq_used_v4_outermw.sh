#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

WSGI="wsgi_vsp_ui_gateway.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC_CANDIDATES=("${VSP_UI_SVC:-vsp-ui-8910.service}" "vsp-ui-8910.service" "vsp-ui-gateway.service")

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need head

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_topfind_contract_v4_${TS}"
echo "[BACKUP] ${WSGI}.bak_topfind_contract_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_TOPFIND_CONTRACT_RID_EQ_USED_WSGIMW_V4"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r'''
# --- VSP_P2_TOPFIND_CONTRACT_RID_EQ_USED_WSGIMW_V4 ---
# Purpose:
# - For /api/vsp/top_findings_v1: ensure JSON contract consistency:
#     if rid_used exists -> rid := rid_used, and keep rid_raw as original rid
# - Works regardless of whether gunicorn serves `application` or `app.wsgi_app`.
import json as _json

def _vsp__is_topfind_path(_p: str) -> bool:
    try:
        return isinstance(_p, str) and (_p == "/api/vsp/top_findings_v1" or _p.startswith("/api/vsp/top_findings_v1"))
    except Exception:
        return False

class _VSPTopFindContractV4MW:
    def __init__(self, _app):
        self._app = _app

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO", "") or ""
        if not _vsp__is_topfind_path(path):
            return self._app(environ, start_response)

        captured = {"status": None, "headers": None, "exc": None}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers) if headers else []
            captured["exc"] = exc_info
            # delay calling real start_response until we finalize body
            return None

        it = self._app(environ, _sr)

        chunks = []
        total = 0
        MAX = 20_000_000  # 20MB safety cap
        try:
            for c in it:
                if c is None:
                    continue
                if isinstance(c, str):
                    c = c.encode("utf-8", "replace")
                chunks.append(c)
                total += len(c)
                if total > MAX:
                    break
        finally:
            close = getattr(it, "close", None)
            if callable(close):
                try: close()
                except Exception: pass

        body = b"".join(chunks)
        status = captured["status"] or "200 OK"
        headers = captured["headers"] or []

        # If too big or empty: pass-through
        if not body or total > MAX:
            start_response(status, headers, captured["exc"])
            return [body]

        # decide json-ish
        hdict = {}
        for k, v in headers:
            hdict[str(k).lower()] = str(v)
        ctype = hdict.get("content-type", "")

        is_json = ("application/json" in ctype.lower()) or body.lstrip().startswith(b"{")
        if not is_json:
            start_response(status, headers, captured["exc"])
            return [body]

        try:
            j = _json.loads(body.decode("utf-8", "replace"))
        except Exception:
            start_response(status, headers, captured["exc"])
            return [body]

        if isinstance(j, dict):
            ru = j.get("rid_used")
            r  = j.get("rid")
            if ru and (r != ru):
                j["rid_raw"] = r
                j["rid"] = ru
                j["marker"] = (j.get("marker") or "") + "|"+ "VSP_P2_TOPFIND_CONTRACT_RID_EQ_USED_WSGIMW_V4"

        out = _json.dumps(j, ensure_ascii=False).encode("utf-8")

        # fix headers: remove Content-Length, set new
        new_headers = []
        for k, v in headers:
            if str(k).lower() == "content-length":
                continue
            new_headers.append((k, v))
        new_headers.append(("Content-Length", str(len(out))))

        start_response(status, new_headers, captured["exc"])
        return [out]

def _vsp__attach_topfind_contract_v4():
    g = globals()
    # Wrap application callable if present
    try:
        if callable(g.get("application")):
            g["application"] = _VSPTopFindContractV4MW(g["application"])
    except Exception:
        pass
    # Wrap Flask app.wsgi_app if present
    try:
        app = g.get("app")
        if app is not None and hasattr(app, "wsgi_app") and callable(app.wsgi_app):
            app.wsgi_app = _VSPTopFindContractV4MW(app.wsgi_app)
    except Exception:
        pass

_vsp__attach_topfind_contract_v4()
# --- /VSP_P2_TOPFIND_CONTRACT_RID_EQ_USED_WSGIMW_V4 ---
'''

s2 = s.rstrip() + "\n\n" + block.lstrip()
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile ok"

echo "== [RESTART] =="
for svc in "${SVC_CANDIDATES[@]}"; do
  [ -n "${svc:-}" ] || continue
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -qE "^${svc}\b"; then
    echo "[DO] sudo systemctl restart $svc"
    sudo systemctl restart "$svc" || true
  fi
done

echo "== [VERIFY] =="
echo "-- rid_latest --"
curl -fsS --max-time 5 "$BASE/api/vsp/rid_latest" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("rid_latest=",j.get("rid"),"via=",j.get("via"))'

echo "-- top_findings --"
curl -fsS --max-time 25 "$BASE/api/vsp/top_findings_v1?limit=5" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("rid=",j.get("rid"),"rid_used=",j.get("rid_used"),"rid_raw=",j.get("rid_raw"),"marker=",j.get("marker"))'
echo "[DONE] Expect: rid == rid_used (rid_raw giữ giá trị cũ nếu từng lệch). Ctrl+Shift+R /vsp5."
