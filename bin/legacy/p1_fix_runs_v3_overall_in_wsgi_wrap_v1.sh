#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
BAK="${F}.bak_fix_runsv3_wsgi_${TS}"
cp -f "$F" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_FIX_RUNS_V3_OVERALL_IN_WSGI_WRAP_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# We patch inside __vsp__wrap_wsgi's inner _app: replace first "return <X>(environ, start_response)"
# with a block that intercepts PATH_INFO==/api/ui/runs_v3, captures status/headers/body, patches JSON, then returns bytes.

# Find a likely return line inside the inner WSGI _app
m = re.search(r'(?m)^\s*return\s+([A-Za-z_]\w*)\s*\(\s*environ\s*,\s*start_response\s*\)\s*$', s)
if not m:
    print("[ERR] cannot find pattern: return <app>(environ, start_response)")
    raise SystemExit(2)

callee = m.group(1)
indent = re.match(r'(?m)^(\s*)return\s+'+re.escape(callee), m.group(0)).group(1)

block = f"""{indent}# {MARK}
{indent}path = ""
{indent}try:
{indent}    path = (environ.get("PATH_INFO") or "")
{indent}except Exception:
{indent}    path = ""

{indent}if path == "/api/ui/runs_v3":
{indent}    _cap = {{}}
{indent}    def _sr(_status, _headers, _exc_info=None):
{indent}        _cap["status"] = _status
{indent}        _cap["headers"] = list(_headers or [])
{indent}        _cap["exc_info"] = _exc_info
{indent}        # WSGI "write" callable (rarely used); we ignore.
{indent}        return (lambda _b: None)

{indent}    _it = {callee}(environ, _sr)
{indent}    try:
{indent}        _body = b"".join(_it)
{indent}    finally:
{indent}        try:
{indent}            close = getattr(_it, "close", None)
{indent}            if callable(close): close()
{indent}        except Exception:
{indent}            pass

{indent}    _status = _cap.get("status") or "200 OK"
{indent}    _headers = _cap.get("headers") or []
{indent}    # content-type check
{indent}    _ct = ""
{indent}    try:
{indent}        for k,v in _headers:
{indent}            if str(k).lower() == "content-type":
{indent}                _ct = str(v)
{indent}                break
{indent}    except Exception:
{indent}        _ct = ""

{indent}    _new_body = _body
{indent}    try:
{indent}        if "application/json" in (_ct or "") and (_body or b"").strip():
{indent}            import json as _json
{indent}            _obj = _json.loads(_body.decode("utf-8", "replace"))
{indent}            if isinstance(_obj, dict) and isinstance(_obj.get("items"), list):
{indent}                for _it2 in _obj["items"]:
{indent}                    if not isinstance(_it2, dict):
{indent}                        continue
{indent}                    _has_gate = bool(_it2.get("has_gate"))
{indent}                    _overall = str(_it2.get("overall") or "").strip().upper()
{indent}                    _counts = _it2.get("counts")
{indent}                    if not isinstance(_counts, dict):
{indent}                        _counts = {{}}
{indent}                    def _i(v, d=0):
{indent}                        try: return int(v) if v is not None else d
{indent}                        except Exception: return d
{indent}                    c = _i(_counts.get("CRITICAL") or _counts.get("critical"), 0)
{indent}                    h = _i(_counts.get("HIGH") or _counts.get("high"), 0)
{indent}                    m = _i(_counts.get("MEDIUM") or _counts.get("medium"), 0)
{indent}                    l = _i(_counts.get("LOW") or _counts.get("low"), 0)
{indent}                    i = _i(_counts.get("INFO") or _counts.get("info"), 0)
{indent}                    t = _i(_counts.get("TRACE") or _counts.get("trace"), 0)
{indent}                    tot = _i(_it2.get("findings_total") or _it2.get("total") or 0, 0)
{indent}                    if (c > 0) or (h > 0):
{indent}                        inf = "RED"
{indent}                    elif (m > 0):
{indent}                        inf = "AMBER"
{indent}                    elif (tot > 0) or ((l+i+t) > 0):
{indent}                        inf = "GREEN"
{indent}                    else:
{indent}                        inf = "GREEN"
{indent}                    # only override when no gate or overall unknown/empty
{indent}                    if (not _has_gate) and ((not _overall) or (_overall == "UNKNOWN")):
{indent}                        _it2["overall"] = inf
{indent}                    _it2["overall_inferred"] = inf
{indent}                    _it2["overall_source"] = ("gate" if (_has_gate and _overall and _overall != "UNKNOWN") else "inferred_counts")
{indent}                _new_body = _json.dumps(_obj, ensure_ascii=False).encode("utf-8")
{indent}    except Exception:
{indent}        _new_body = _body

{indent}    # rebuild headers with corrected content-length
{indent}    _h2 = []
{indent}    for k,v in _headers:
{indent}        if str(k).lower() == "content-length":
{indent}            continue
{indent}        _h2.append((k,v))
{indent}    _h2.append(("Content-Length", str(len(_new_body))))
{indent}    start_response(_status, _h2, _cap.get("exc_info"))
{indent}    return [_new_body]

{indent}return {callee}(environ, start_response)
"""

s2 = s[:m.start()] + block + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched WSGI wrapper return hook, callee=", callee)
PY

# transactional compile
if ! python3 -m py_compile wsgi_vsp_ui_gateway.py; then
  echo "[ERR] py_compile failed -> restore $BAK"
  cp -f "$BAK" wsgi_vsp_ui_gateway.py
  python3 -m py_compile wsgi_vsp_ui_gateway.py || true
  exit 3
fi
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service || true

echo "== verify =="
curl -sS "http://127.0.0.1:8910/api/ui/runs_v3?limit=1" | python3 -c '
import sys,json
d=json.load(sys.stdin)
it=(d.get("items") or [{}])[0]
print("rid=", it.get("rid"))
print("overall=", it.get("overall"), "src=", it.get("overall_source"), "inf=", it.get("overall_inferred"))
print("counts=", it.get("counts"))
'
