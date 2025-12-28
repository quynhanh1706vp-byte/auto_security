#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
BROKEN_BAK="${F}.bak_broken_snapshot_${TS}"
cp -f "$F" "$BROKEN_BAK"
echo "[SNAPSHOT] $BROKEN_BAK"

echo "== find latest compiling backup =="
GOOD="$(python3 - <<'PY'
from pathlib import Path
import py_compile

p = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda x: x.stat().st_mtime, reverse=True)

def ok(path: Path) -> bool:
    try:
        py_compile.compile(str(path), doraise=True)
        return True
    except Exception:
        return False

for b in baks:
    if ok(b):
        print(str(b))
        raise SystemExit(0)

print("")
raise SystemExit(1)
PY
)"

if [ -z "${GOOD:-}" ]; then
  echo "[ERR] no compiling backup found. You must inspect older copies manually."
  echo "[INFO] recent backups:"
  ls -1t wsgi_vsp_ui_gateway.py.bak_* 2>/dev/null | head -n 20 || true
  exit 3
fi

echo "[OK] restoring GOOD backup: $GOOD"
cp -f "$GOOD" "$F"
python3 -m py_compile "$F" && echo "[OK] restored file compiles"

echo "== apply WSGI wrap for /api/ui/runs_v3 overall inference (V2) =="
python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_FIX_RUNS_V3_OVERALL_WRAPAPP_V2"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

patch = r'''
# VSP_P1_FIX_RUNS_V3_OVERALL_WRAPAPP_V2
def __vsp__wrap_runs_v3_overall_v2(_orig_callable):
    def _w(environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
        except Exception:
            path = ""
        if path == "/api/ui/runs_v3":
            _cap = {}
            def _sr(_status, _headers, _exc_info=None):
                _cap["status"] = _status
                _cap["headers"] = list(_headers or [])
                _cap["exc_info"] = _exc_info
                return (lambda _b: None)

            _it = _orig_callable(environ, _sr)
            try:
                _body = b"".join(_it)
            finally:
                try:
                    _close = getattr(_it, "close", None)
                    if callable(_close):
                        _close()
                except Exception:
                    pass

            _status = _cap.get("status") or "200 OK"
            _headers = _cap.get("headers") or []
            _ct = ""
            try:
                for k, v in _headers:
                    if str(k).lower() == "content-type":
                        _ct = str(v)
                        break
            except Exception:
                _ct = ""

            _new_body = _body
            try:
                if "application/json" in (_ct or "") and (_body or b"").strip():
                    import json as _json
                    _obj = _json.loads(_body.decode("utf-8", "replace"))
                    if isinstance(_obj, dict) and isinstance(_obj.get("items"), list):
                        for _it2 in _obj["items"]:
                            if not isinstance(_it2, dict):
                                continue
                            _has_gate = bool(_it2.get("has_gate"))
                            _overall = str(_it2.get("overall") or "").strip().upper()
                            _counts = _it2.get("counts")
                            if not isinstance(_counts, dict):
                                _counts = {}
                            def _i(v, d=0):
                                try:
                                    return int(v) if v is not None else d
                                except Exception:
                                    return d
                            c = _i(_counts.get("CRITICAL") or _counts.get("critical"), 0)
                            h = _i(_counts.get("HIGH") or _counts.get("high"), 0)
                            m = _i(_counts.get("MEDIUM") or _counts.get("medium"), 0)
                            l = _i(_counts.get("LOW") or _counts.get("low"), 0)
                            i = _i(_counts.get("INFO") or _counts.get("info"), 0)
                            t = _i(_counts.get("TRACE") or _counts.get("trace"), 0)
                            tot = _i(_it2.get("findings_total") or _it2.get("total") or 0, 0)

                            if (c > 0) or (h > 0):
                                inf = "RED"
                            elif (m > 0):
                                inf = "AMBER"
                            elif (tot > 0) or ((l + i + t) > 0):
                                inf = "GREEN"
                            else:
                                inf = "GREEN"

                            if (not _has_gate) and ((not _overall) or (_overall == "UNKNOWN")):
                                _it2["overall"] = inf
                            _it2["overall_inferred"] = inf
                            _it2["overall_source"] = ("gate" if (_has_gate and _overall and _overall != "UNKNOWN") else "inferred_counts")

                        _new_body = _json.dumps(_obj, ensure_ascii=False).encode("utf-8")
            except Exception:
                _new_body = _body

            _h2 = []
            for k, v in _headers:
                if str(k).lower() == "content-length":
                    continue
                _h2.append((k, v))
            _h2.append(("Content-Length", str(len(_new_body))))
            start_response(_status, _h2, _cap.get("exc_info"))
            return [_new_body]

        return _orig_callable(environ, start_response)
    return _w

def __vsp__maybe_wrap_callable_v2(name):
    try:
        obj = globals().get(name)
        if obj is None:
            return False
        # wrap only plain callables (functions), not Flask app objects
        try:
            from flask import Flask
            if isinstance(obj, Flask):
                return False
        except Exception:
            pass
        if callable(obj):
            globals()[name] = __vsp__wrap_runs_v3_overall_v2(obj)
            return True
        return False
    except Exception:
        return False

_wrapped = []
for _n in ("app", "application"):
    if __vsp__maybe_wrap_callable_v2(_n):
        _wrapped.append(_n)
print("[VSP_FIX_RUNS_V3_WRAPAPP_V2] wrapped:", _wrapped)
'''.lstrip("\n")

# append at EOF (safe, avoids indent/regex issues)
s2 = s.rstrip() + "\n\n" + patch + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended", MARK)
PY

# transactional compile: if fails, restore GOOD backup immediately
if ! python3 -m py_compile "$F"; then
  echo "[ERR] compile failed after patch -> restoring GOOD=$GOOD"
  cp -f "$GOOD" "$F"
  python3 -m py_compile "$F" || true
  exit 4
fi
echo "[OK] py_compile OK after patch"

echo "== restart service =="
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
