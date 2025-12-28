#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# (A) Fix keepalive URL quoting + ensure file exists
KEEP="static/js/vsp_ui_keepalive_p1_2.js"
mkdir -p static/js
if [ ! -f "$KEEP" ]; then
  cat > "$KEEP" <<'JS'
/* VSP_UI_KEEPALIVE_P1_2_STUB */
(function(){
  try{
    if (window.__vsp_keepalive_p1_2_stub) return;
    window.__vsp_keepalive_p1_2_stub = true;
    // noop keepalive stub (real keepalive may live elsewhere)
    console.info("[VSP] keepalive stub loaded");
  }catch(_){}
})();
JS
  echo "[OK] created stub: $KEEP"
fi

python3 - <<'PY'
from pathlib import Path
import re, time

roots = [Path("templates"), Path("static/js")]
pat_bad = re.compile(r'127\.0\.0\.1:8910%22/|%22/static/', re.I)

patched = 0
for root in roots:
    if not root.exists(): 
        continue
    for p in root.rglob("*"):
        if not p.is_file(): 
            continue
        if p.suffix not in (".html",".js"):
            continue
        s = p.read_text(encoding="utf-8", errors="replace")
        if ("%22" not in s) and ("vsp_ui_keepalive_p1_2.js" not in s):
            continue
        s2 = s
        # normalize any absolute/quoted URL -> relative
        s2 = s2.replace("http://127.0.0.1:8910%22/static/js/vsp_ui_keepalive_p1_2.js", "/static/js/vsp_ui_keepalive_p1_2.js")
        s2 = s2.replace("http://127.0.0.1:8910/static/js/vsp_ui_keepalive_p1_2.js", "/static/js/vsp_ui_keepalive_p1_2.js")
        s2 = pat_bad.sub("/", s2)
        if s2 != s:
            bak = Path(str(p) + f".bak_keepalivefix_{int(time.time())}")
            bak.write_text(s, encoding="utf-8")
            p.write_text(s2, encoding="utf-8")
            patched += 1
print("[OK] keepalive quote/url normalized in files:", patched)
PY

# (B) Add /api/vsp/runs fallback middleware (return 200 JSON when downstream 5xx)
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_runs503fix_${TS}"
echo "[BACKUP] ${F}.bak_runs503fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, json, urllib.parse, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_RUNS_503_FALLBACK_MW_P1_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

inject = r'''
# === VSP_P1_RUNS_503_FALLBACK_MW_P1_V1 ===
import json as _json
from pathlib import Path as _Path
import time as _time
import urllib.parse as _urlparse

class _VspRuns503FallbackMWP1V1:
    def __init__(self, app):
        self.app = app

    def _scan_runs(self, limit=20):
        roots = [
            _Path("/home/test/Data/SECURITY_BUNDLE/out"),
            _Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
            _Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        ]
        dirs=[]
        for r in roots:
            try:
                if not r.exists(): 
                    continue
                for d in r.iterdir():
                    if not d.is_dir(): 
                        continue
                    name=d.name
                    if "RUN_" not in name:
                        continue
                    try:
                        mt = d.stat().st_mtime
                    except Exception:
                        mt = 0
                    dirs.append((mt, name))
            except Exception:
                pass
        dirs.sort(reverse=True)
        items=[]
        for mt, name in dirs[:max(1,int(limit))]:
            items.append({
                "run_id": name,
                "mtime": mt,
                "has": {"csv": False, "html": False, "json": False, "sarif": False, "summary": False}
            })
        return items

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/vsp/runs"):
            return self.app(environ, start_response)

        captured = {"status": None, "headers": None, "exc": None}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers) if headers else []
            captured["exc"] = exc_info
            def _write(_data): return None
            return _write

        try:
            it = self.app(environ, _sr)
            chunks=[]
            try:
                for c in it:
                    if c: chunks.append(c)
            finally:
                try:
                    close=getattr(it,"close",None)
                    if callable(close): close()
                except Exception:
                    pass
            body = b"".join(chunks)
            code = 200
            try:
                code = int((captured["status"] or "200").split()[0])
            except Exception:
                code = 200

            # if downstream OK -> return as-is
            if code < 500:
                start_response(captured["status"] or "200 OK", captured["headers"] or [], captured["exc"])
                return [body]

        except Exception:
            code = 503

        # FALLBACK JSON 200
        try:
            qs = (environ.get("QUERY_STRING") or "")
            q = _urlparse.parse_qs(qs)
            limit = int((q.get("limit") or [20])[0])
        except Exception:
            limit = 20

        items = self._scan_runs(limit=limit)
        payload = {
            "ok": True,
            "fallback": True,
            "items": items,
            "limit": limit,
            "error": "downstream /api/vsp/runs failed (>=500), served fallback list"
        }
        out = _json.dumps(payload, ensure_ascii=False).encode("utf-8")
        hdrs = [("Content-Type","application/json; charset=utf-8"),
                ("Content-Length", str(len(out))),
                ("Cache-Control","no-cache"),
                ("X-VSP-RUNS-FALLBACK","1")]
        start_response("200 OK", hdrs)
        return [out]

# wrap last
try:
    application = _VspRuns503FallbackMWP1V1(application)
except Exception:
    pass
# === /VSP_P1_RUNS_503_FALLBACK_MW_P1_V1 ===
'''
p.write_text(s + "\n\n" + inject + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

echo "[NEXT] restart service"
