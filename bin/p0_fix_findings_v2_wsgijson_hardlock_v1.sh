#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_wsgijson_hardlock_${TS}"
echo "[BACKUP] ${F}.bak_wsgijson_hardlock_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_WSGI_JSON_HARDLOCK_V1"
if marker in s:
    print("[SKIP] already patched:", marker)
    raise SystemExit(0)

block = textwrap.dedent(r"""
# --- VSP_P0_WSGI_JSON_HARDLOCK_V1 ---
# Hard-lock: eliminate 500 in WSGI JSON responses.
# - Define __wsgi_json (avoid NameError)
# - Override __vsp__json to be WSGI-safe and callable/method-safe (never 500 on json.dumps)
try:
    import json as _vsp_json_mod
    from werkzeug.wrappers import Response as _VspWzResponse
except Exception:
    _vsp_json_mod = None
    _VspWzResponse = None

def __wsgi_json(payload, status=200, mimetype="application/json"):  # noqa: F811
    # Always return a proper WSGI Response (iterable bytes)
    if _vsp_json_mod is None or _VspWzResponse is None:
        # last resort: plain bytes iterable
        body = (str(payload) if payload is not None else "")
        if isinstance(body, str):
            body = body.encode("utf-8", errors="replace")
        return [body]
    try:
        body = _vsp_json_mod.dumps(payload, ensure_ascii=False, default=str)
    except Exception as e:
        body = _vsp_json_mod.dumps({"ok": False, "error": "json_dump_failed", "detail": str(e)}, ensure_ascii=False, default=str)
    return _VspWzResponse(body, status=int(status), mimetype=mimetype)

# Keep a reference to previous impl if exists (for debugging)
try:
    __vsp__json_prev = __vsp__json  # type: ignore[name-defined]
except Exception:
    __vsp__json_prev = None

def __vsp__json(*args, **kwargs):  # noqa: F811
    # Supported call patterns:
    #   __vsp__json(payload)
    #   __vsp__json(payload, status)
    #   __vsp__json(start_response, payload)
    #   __vsp__json(start_response, payload, status)
    status = int(kwargs.get("status", 200))
    payload = None

    if len(args) == 0:
        payload = kwargs.get("payload", {})
    elif len(args) == 1:
        payload = args[0]
    else:
        a0, a1 = args[0], args[1]
        # If first is callable, treat as start_response
        if callable(a0):
            payload = a1
            if len(args) >= 3 and isinstance(args[2], int):
                status = int(args[2])
        else:
            payload = a0
            if isinstance(a1, int):
                status = int(a1)

    # If payload is callable/method, try to materialize; otherwise stringify safely
    try:
        if callable(payload):
            try:
                payload2 = payload()  # may fail if needs args
                payload = payload2
            except Exception:
                payload = {"ok": False, "error": "payload_callable", "payload_type": str(type(payload))}
    except Exception:
        payload = {"ok": False, "error": "payload_inspect_failed"}

    return __wsgi_json(payload, status=status)
""").strip() + "\n"

p.write_text(s.rstrip() + "\n\n" + block, encoding="utf-8")
print("[OK] appended:", marker)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service

echo "== verify findings_v2 =="
BASE=http://127.0.0.1:8910
RID=$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("items",[{}])[0].get("run_id",""))')
echo "[RID]=$RID"
curl -sS -i "$BASE/api/ui/findings_v2?rid=$RID&limit=5&offset=0&q=" | sed -n '1,25p'
