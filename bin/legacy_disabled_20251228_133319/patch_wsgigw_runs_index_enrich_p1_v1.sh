#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runsindexmw_${TS}" && echo "[BACKUP] $F.bak_runsindexmw_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="# === VSP_WSGI_RUNS_INDEX_ENRICH_MW_P1_V1_BEGIN ==="
END  ="# === VSP_WSGI_RUNS_INDEX_ENRICH_MW_P1_V1_END ==="

block = r'''
{BEGIN}
import json
import urllib.parse

class VSPRunsIndexEnrichMWP1V1:
    """
    Post-process /api/vsp/runs_index_v3_fs_resolved JSON items by attaching:
      total_findings, has_findings, degraded_n, degraded_any
    derived deterministically from ci_run_dir (no heuristics).
    """
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO","") or ""
        if path != "/api/vsp/runs_index_v3_fs_resolved":
            return self.app(environ, start_response)

        captured = {"status":"200 OK","headers":[],"exc":None}
        def _sr(status, headers, exc_info=None):
            captured["status"]=status
            captured["headers"]=headers or []
            captured["exc"]=exc_info

        it = self.app(environ, _sr)
        try:
            body = b"".join(it)
        finally:
            try: it.close()
            except Exception: pass

        headers = captured["headers"]
        ctype=""
        for k,v in headers:
            if str(k).lower()=="content-type":
                ctype=str(v); break
        if "application/json" not in ctype.lower():
            start_response(captured["status"], headers, captured["exc"])
            return [body]

        try:
            obj=json.loads(body.decode("utf-8","ignore"))
        except Exception:
            start_response(captured["status"], headers, captured["exc"])
            return [body]

        if not isinstance(obj, dict):
            start_response(captured["status"], headers, captured["exc"])
            return [body]

        items = obj.get("items")
        if not isinstance(items, list):
            start_response(captured["status"], headers, captured["exc"])
            return [body]

        # cap enrich to avoid heavy IO if someone requests huge limit
        qs = environ.get("QUERY_STRING","") or ""
        q = urllib.parse.parse_qs(qs)
        try:
            limit = int((q.get("limit") or ["50"])[0])
        except Exception:
            limit = 50
        hard_cap = 120
        n = min(len(items), min(limit, hard_cap))

        for i in range(n):
            it0 = items[i]
            if not isinstance(it0, dict):
                continue
            run_dir = it0.get("ci_run_dir") or it0.get("ci") or None
            if not run_dir:
                continue
            try:
                # reuse helpers from status MW (already injected earlier)
                t = _vsp_findings_total(run_dir)
                if isinstance(t, int):
                    it0["total_findings"] = t
                    it0["has_findings"] = True if t>0 else False
                dn, da = _vsp_degraded_info(run_dir)
                if isinstance(dn, int):
                    it0["degraded_n"] = dn
                if isinstance(da, bool):
                    it0["degraded_any"] = da
            except Exception:
                pass

        out=json.dumps(obj, ensure_ascii=False).encode("utf-8")

        new_headers=[]
        for k,v in headers:
            if str(k).lower()=="content-length":
                continue
            new_headers.append((k,v))
        new_headers.append(("Content-Length", str(len(out))))

        start_response(captured["status"], new_headers, captured["exc"])
        return [out]

try:
    application = VSPRunsIndexEnrichMWP1V1(application)
except Exception:
    pass
{END}
'''.replace("{BEGIN}", BEGIN).replace("{END}", END)

if BEGIN in s and END in s:
    s = re.sub(re.escape(BEGIN)+r".*?"+re.escape(END), block, s, flags=re.S)
else:
    s = s.rstrip() + "\n\n" + block + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] injected runs_index enrich middleware")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile OK => $F"
