#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need ls; need head

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
PRE="${W}.pre_rescue_${TS}"
cp -f "$W" "$PRE"
echo "[BACKUP] $PRE"

# Restore from the backup created right before V7 was appended (best effort)
BK="$(ls -1t ${W}.bak_topfind_force_ridlatest_v7_* 2>/dev/null | head -n 1 || true)"
if [ -n "${BK:-}" ]; then
  cp -f "$BK" "$W"
  echo "[OK] restored $W from $BK"
else
  echo "[WARN] no .bak_topfind_force_ridlatest_v7_* found; will patch in-place"
fi

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Remove any old V7 block if exists (in case restore didn't happen)
s = re.sub(
    r"\n?# === VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7 ===.*?# === /VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7 ===\n?",
    "\n",
    s,
    flags=re.S
)

MARK="VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7B"
if MARK in s:
    print("[OK] already patched (marker exists)")
    p.write_text(s, encoding="utf-8")
    raise SystemExit(0)

patch = r'''
# === VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7B ===
# Fix đúng chuẩn: KHÔNG replay raw response nữa (tránh bể HTTP/curl).
# Chỉ rewrite QUERY_STRING để thêm rid=<rid_latest> rồi delegate app gốc trả response.

try:
    import json as _json
    import io as _io
    import urllib.parse as _up
except Exception:
    _json=None
    _io=None
    _up=None

class __VspTopFindForceRidLatestMwV7B:
    def __init__(self, app):
        self.app = app

    def _get_rid_latest(self):
        # Internal WSGI call to /api/vsp/rid_latest (no HTTP socket)
        if _io is None or _json is None:
            return None

        status_holder={"status":None, "headers":[]}
        def _sr(status, headers, exc_info=None):
            status_holder["status"]=status
            status_holder["headers"]=list(headers or [])
            return None

        env={
            "REQUEST_METHOD":"GET",
            "SCRIPT_NAME":"",
            "PATH_INFO":"/api/vsp/rid_latest",
            "QUERY_STRING":"",
            "SERVER_NAME":"localhost",
            "SERVER_PORT":"0",
            "SERVER_PROTOCOL":"HTTP/1.1",
            "wsgi.version":(1,0),
            "wsgi.url_scheme":"http",
            "wsgi.input":_io.BytesIO(b""),
            "wsgi.errors":_io.StringIO(),
            "wsgi.multithread":False,
            "wsgi.multiprocess":True,
            "wsgi.run_once":False,
            "CONTENT_LENGTH":"0",
            "HTTP_X_VSP_INTERNAL_CALL":"1",
        }

        chunks=[]
        try:
            it=self.app(env,_sr)
            for c in it:
                if c: chunks.append(c)
            try:
                close=getattr(it,"close",None)
                if callable(close): close()
            except Exception:
                pass
        except Exception:
            return None

        st=(status_holder["status"] or "000").split(" ",1)[0]
        try: code=int(st)
        except Exception: code=0

        ctype=""
        for k,v in (status_holder["headers"] or []):
            if str(k).lower()=="content-type":
                ctype=str(v); break

        if code!=200 or "application/json" not in ctype.lower():
            return None

        body=b"".join(chunks)
        try:
            j=_json.loads(body.decode("utf-8", errors="replace"))
        except Exception:
            return None

        if isinstance(j, dict) and j.get("ok") in (True,"true",1):
            return j.get("rid")
        return None

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO") or ""
        if path != "/api/vsp/top_findings_v1":
            return self.app(environ, start_response)

        # recursion guard
        if environ.get("HTTP_X_VSP_INTERNAL_CALL") == "1":
            return self.app(environ, start_response)

        # wrap start_response to de-dup header proof + set single marker
        def _sr_wrap(status, headers, exc_info=None, marker="passthrough"):
            h=[]
            for (k,v) in (headers or []):
                if str(k).lower() == "x-vsp-topfind-runid-fix":
                    continue
                h.append((k,v))
            h.append(("X-VSP-TOPFIND-RUNID-FIX", marker))
            return start_response(status, h, exc_info)

        if _up is None:
            return self.app(environ, lambda st, hd, ex=None: _sr_wrap(st, hd, ex, "no-urllib"))

        qs = environ.get("QUERY_STRING") or ""
        q = _up.parse_qs(qs, keep_blank_values=True)

        # If client already passes rid= -> keep, only normalize header marker
        if "rid" in q and (q["rid"] and q["rid"][0]):
            return self.app(environ, lambda st, hd, ex=None: _sr_wrap(st, hd, ex, "passthrough"))

        rid = self._get_rid_latest()
        if not rid:
            return self.app(environ, lambda st, hd, ex=None: _sr_wrap(st, hd, ex, "no-ridlatest"))

        # Rewrite query string to include rid=<rid_latest>, keep other params (limit...)
        q["rid"] = [str(rid)]
        new_qs = _up.urlencode(q, doseq=True)

        env2 = dict(environ)
        env2["QUERY_STRING"] = new_qs
        env2["HTTP_X_VSP_INTERNAL_CALL"] = "1"

        return self.app(env2, lambda st, hd, ex=None: _sr_wrap(st, hd, ex, "ok-v7b"))

# Install on outermost WSGI callable
try:
    _base = globals().get("application") or globals().get("app")
    if _base is not None and _base.__class__.__name__ != "__VspTopFindForceRidLatestMwV7B":
        globals()["application"] = __VspTopFindForceRidLatestMwV7B(_base)
except Exception:
    pass
# === /VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7B ===
'''

p.write_text(s + "\n" + patch, encoding="utf-8")
print("[OK] appended", MARK)
PY

python3 -m py_compile "$W" >/dev/null
echo "[OK] py_compile OK"

echo "[INFO] restarting: $SVC"
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active"

echo "== PROOF headers (HEAD, must NOT curl-error) =="
curl --http1.1 -sSI "$BASE/api/vsp/top_findings_v1?limit=1" | egrep -i 'http/|content-type|x-vsp-topfind-runid-fix' || true

echo "== PROOF body (must be JSON, rid_used==rid_latest) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "rid_latest=$RID"
curl --http1.1 -sS "$BASE/api/vsp/top_findings_v1?limit=1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),
      "rid_used=",j.get("rid_used"),
      "run_id=",j.get("run_id"),
      "marker=",j.get("marker"),
      "total=",j.get("total"))
PY

echo "== PROOF explicit rid=rid_latest (must match) =="
curl --http1.1 -sS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),
      "rid_used=",j.get("rid_used"),
      "run_id=",j.get("run_id"),
      "total=",j.get("total"))
PY

echo "[OK] done"
