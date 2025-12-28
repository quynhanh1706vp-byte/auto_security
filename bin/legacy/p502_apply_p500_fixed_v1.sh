#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="wsgi_vsp_ui_gateway.py"
[ -f "$T" ] || T="vsp_demo_app.py"
[ -f "$T" ] || { echo "[ERR] missing wsgi_vsp_ui_gateway.py and vsp_demo_app.py"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p502_${TS}"
mkdir -p "$OUT"
cp -f "$T" "$OUT/$(basename "$T").bak_${TS}"
echo "[OK] target=$T backup=$OUT/$(basename "$T").bak_${TS}"

python3 - <<'PY' "$T"
from pathlib import Path
import sys, re
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

# remove old broken P500 block if still present
s = re.sub(r"\n# VSP_P500_TINYCACHE_AND_RUNSV3_FILTER_V1[\s\S]*?\n(?=\Z)", "\n", s, flags=re.M)

MARK="VSP_P500B_TINYCACHE_AND_RUNSV3_FILTER_FIXED_V1"
if MARK in s:
    print("[OK] already patched")
    sys.exit(0)

snippet = r'''
# VSP_P500B_TINYCACHE_AND_RUNSV3_FILTER_FIXED_V1
# - tiny TTL cache for heavy GET endpoints (safe WSGI start_response)
# - filter out selfcheck runs (rid/run_id prefix p49*/p490*) from runs_v3 JSON
import time, json

class _VSPTinyCacheFixedV1:
    def __init__(self, app, ttl=2.0, max_body=2_000_000):
        self.app = app
        self.ttl = float(ttl)
        self.max_body = int(max_body)
        self._cache = {}  # key -> (ts, status, headers, body_bytes)
        self.cache_paths = set([
            "/api/vsp/top_findings_v2",
            "/api/vsp/rule_overrides",
            "/api/vsp/overrides",
            "/api/vsp/run_file_allow",
        ])

    def _now(self): return time.time()

    def _hdr_get(self, headers, name):
        n=name.lower()
        for k,v in headers:
            if (k or "").lower()==n: return v
        return ""

    def _hdr_set(self, headers, name, value):
        n=name.lower()
        out=[]; found=False
        for k,v in headers:
            if (k or "").lower()==n:
                out.append((k,value)); found=True
            else:
                out.append((k,v))
        if not found: out.append((name,value))
        return out

    def _filter_runs_v3(self, path, headers, body):
        if path != "/api/vsp/runs_v3": return headers, body
        ct=self._hdr_get(headers,"Content-Type") or ""
        if "application/json" not in ct: return headers, body
        try:
            obj=json.loads(body.decode("utf-8","replace"))
            if not isinstance(obj,dict): return headers, body

            def keep(x):
                if not isinstance(x,dict): return True
                rid=(x.get("rid") or x.get("run_id") or "").strip()
                return not (rid.startswith("p49") or rid.startswith("p490"))

            for k in ("runs","items"):
                if isinstance(obj.get(k),list):
                    obj[k]=[x for x in obj[k] if keep(x)]

            body2=json.dumps(obj,ensure_ascii=False).encode("utf-8")
            headers2=self._hdr_set(headers,"Content-Length",str(len(body2)))
            headers2=self._hdr_set(headers2,"X-VSP-P500B-RUNS3-FILTER","1")
            return headers2, body2
        except Exception:
            return headers, body

    def __call__(self, environ, start_response):
        method=(environ.get("REQUEST_METHOD") or "GET").upper()
        path=environ.get("PATH_INFO") or ""
        qs=environ.get("QUERY_STRING") or ""
        key=(method,path,qs)

        # serve cache
        if method=="GET" and path in self.cache_paths:
            ent=self._cache.get(key)
            if ent:
                ts,status,headers,body=ent
                if self._now()-ts <= self.ttl:
                    headers=self._hdr_set(headers,"X-VSP-P500B-CACHE","HIT")
                    start_response(status, headers)
                    return [body]

        captured={"status":"200 OK","headers":[], "exc":None}
        write_buf=[]

        def _sr(status, headers, exc_info=None):
            captured["status"]=status
            captured["headers"]=list(headers or [])
            captured["exc"]=exc_info
            def _write(data):
                if data:
                    write_buf.append(data if isinstance(data,(bytes,bytearray)) else str(data).encode("utf-8","replace"))
            return _write

        it=None
        try:
            it=self.app(environ, _sr)
            body=b"".join(write_buf + list(it or []))
        finally:
            try:
                if hasattr(it, "close"): it.close()
            except Exception:
                pass

        status=captured["status"]
        headers=captured["headers"]

        # filter runs_v3 if needed
        headers, body = self._filter_runs_v3(path, headers, body)

        # cache store (only small-ish bodies)
        if method=="GET" and path in self.cache_paths and len(body) <= self.max_body:
            headers=self._hdr_set(headers,"X-VSP-P500B-CACHE","MISS")
            self._cache[key]=(self._now(), status, headers, body)

        headers=self._hdr_set(headers,"Content-Length",str(len(body)))
        start_response(status, headers, captured.get("exc"))
        return [body]

def _vsp_p500b_wrap(app_obj):
    try:
        if hasattr(app_obj, "wsgi_app"):
            app_obj.wsgi_app = _VSPTinyCacheFixedV1(app_obj.wsgi_app, ttl=2.0)
            return app_obj
    except Exception:
        pass
    try:
        if callable(app_obj):
            return _VSPTinyCacheFixedV1(app_obj, ttl=2.0)
    except Exception:
        pass
    return app_obj

try:
    if "app" in globals():
        globals()["app"]=_vsp_p500b_wrap(globals()["app"])
    if "application" in globals():
        globals()["application"]=_vsp_p500b_wrap(globals()["application"])
except Exception:
    pass
'''

p.write_text(s.rstrip()+"\n\n"+snippet+"\n", encoding="utf-8")
print("[OK] patched", p)
PY

python3 -m py_compile "$T" && echo "[OK] py_compile $T"
echo "[OK] patched. Restart service now."
