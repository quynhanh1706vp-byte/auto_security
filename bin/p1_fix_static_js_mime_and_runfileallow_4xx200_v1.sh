#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_staticjs_runfile_${TS}"
echo "[BACKUP] ${W}.bak_staticjs_runfile_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, textwrap, re

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")

# 1) Ensure shims exist for any referenced vsp_data_source_lazy*.js
tpl_dir = Path("templates")
names = set()
if tpl_dir.is_dir():
    for p in tpl_dir.rglob("*.html"):
        t = p.read_text(encoding="utf-8", errors="replace")
        for m in re.findall(r'/static/js/(vsp_data_source_lazy[^"\']+\.js)', t):
            names.add(m)

if not names:
    names.add("vsp_data_source_lazy_v1.js")

static_js = Path("static/js")
static_js.mkdir(parents=True, exist_ok=True)

shim_body = lambda targets: textwrap.dedent(f"""
/* VSP_P1_DATA_SOURCE_LAZY_SHIM_V1B
   - Prevent MIME JSON execution block (server must serve this as JS)
   - Loads real Data Source modules if present.
*/
(()=>{{
  try {{
    const ver = String(Date.now());
    const targets = {targets!r};
    const load = (src)=> new Promise((res)=>{{
      const s=document.createElement('script');
      s.src='/static/js/'+src + (src.includes('?') ? '' : ('?v='+ver));
      s.async=true;
      s.onload=()=>res(true);
      s.onerror=()=>res(false);
      document.head.appendChild(s);
    }});
    (async()=>{{
      for(const t of targets) {{ try{{ await load(t); }}catch(e){{}} }}
      try{{ console.log("[DataSourceLazyShimV1B] loaded:", targets.join(", ")); }}catch(e){{}}
    }})();
  }} catch(e){{}}
}})();
""").strip()+"\n"

# pick real DS modules
cands = ["vsp_data_source_tab_v3.js","vsp_data_source_tab_v2.js","vsp_data_source_charts_v1.js"]
targets = [x for x in cands if (static_js/x).exists()]
if not targets:
    targets = ["vsp_data_source_tab_v3.js"]

for name in sorted(names):
    f = static_js / name
    if not f.exists():
        f.write_text(shim_body(targets[:2]), encoding="utf-8")

print("[OK] ensured datasource lazy shims:", ", ".join(sorted(names)))

# 2) Add middleware: force filesystem serve for /static/js/*.js if file exists
MARK1="VSP_P1_GATEWAY_STATIC_JS_FILESERVE_V1"
if MARK1 not in s:
    block1 = textwrap.dedent(r"""
# ===================== VSP_P1_GATEWAY_STATIC_JS_FILESERVE_V1 =====================
def _vsp_mw_static_js_fileserve_v1(app):
    import os
    from pathlib import Path

    base_dir = Path(__file__).resolve().parent
    js_dir = base_dir / "static" / "js"

    def _ctype(path: str) -> str:
        # strict enough for Chrome
        if path.endswith(".js"):
            return "application/javascript; charset=utf-8"
        return "application/octet-stream"

    def middleware(environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            if not path.startswith("/static/js/"):
                return app(environ, start_response)

            name = path[len("/static/js/"):]
            # deny traversal
            if (not name) or (".." in name) or ("/" in name) or ("\\" in name):
                return app(environ, start_response)

            fpath = js_dir / name
            if not fpath.is_file():
                return app(environ, start_response)

            data = fpath.read_bytes()
            hdrs = [
                ("Content-Type", _ctype(name)),
                ("Cache-Control", "no-store"),
                ("X-VSP-STATIC-FS", "1"),
                ("Content-Length", str(len(data))),
            ]
            start_response("200 OK", hdrs)
            return [data]
        except Exception:
            return app(environ, start_response)

    return middleware

try:
    if "application" in globals() and callable(globals().get("application")):
        application = _vsp_mw_static_js_fileserve_v1(application)
except Exception:
    pass
try:
    if "app" in globals() and callable(globals().get("app")):
        app = _vsp_mw_static_js_fileserve_v1(app)
except Exception:
    pass
# ===================== /VSP_P1_GATEWAY_STATIC_JS_FILESERVE_V1 =====================
""").strip()+"\n"
    s = s.rstrip()+"\n\n"+block1
    print("[OK] injected:", MARK1)
else:
    print("[OK] already present:", MARK1)

# 3) Wrap run_file_allow any >=400 into 200 JSON (commercial-stable)
MARK2="VSP_P1_RUN_FILE_ALLOW_WRAP_4XX5XX_TO_200_V1"
if MARK2 not in s:
    block2 = textwrap.dedent(r"""
# ===================== VSP_P1_RUN_FILE_ALLOW_WRAP_4XX5XX_TO_200_V1 =====================
def _vsp_mw_run_file_allow_wrap_4xx5xx_to_200_v1(app):
    import json
    target_paths = {"/api/vsp/run_file_allow", "/api/vsp/run_file_allow/"}

    def middleware(environ, start_response):
        path = (environ.get("PATH_INFO") or "").rstrip("/") or "/"
        if path not in {p.rstrip("/") for p in target_paths}:
            return app(environ, start_response)

        captured = {"status": None, "headers": None}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers) if headers else []
            return lambda x: None

        resp_iter = app(environ, _sr)
        status = captured["status"] or "200 OK"
        code = 200
        try:
            code = int(status.split()[0])
        except Exception:
            code = 200

        # pass through if OK
        if code < 400:
            start_response(status, captured["headers"] or [])
            return resp_iter

        # buffer upstream body best-effort
        try:
            up = b"".join(resp_iter)
        except Exception:
            up = b""
        finally:
            try:
                close = getattr(resp_iter, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        # if upstream body is JSON, try keep it (so UI can still see allowlist details)
        payload = None
        try:
            payload = json.loads(up.decode("utf-8", "ignore")) if up else None
        except Exception:
            payload = None

        if isinstance(payload, dict):
            payload.setdefault("ok", False)
            payload.setdefault("err", "wrapped_non200")
            payload.setdefault("upstream_status", status)
        else:
            payload = {
                "ok": False,
                "err": "wrapped_non200",
                "upstream_status": status,
                "upstream_body_snip": (up[:400].decode("utf-8", "ignore") if up else "")
            }

        out = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Cache-Control", "no-store"),
            ("X-VSP-WRAP", "run_file_allow_4xx5xx_to_200"),
            ("Content-Length", str(len(out))),
        ]
        start_response("200 OK", headers)
        return [out]

    return middleware

try:
    if "application" in globals() and callable(globals().get("application")):
        application = _vsp_mw_run_file_allow_wrap_4xx5xx_to_200_v1(application)
except Exception:
    pass
try:
    if "app" in globals() and callable(globals().get("app")):
        app = _vsp_mw_run_file_allow_wrap_4xx5xx_to_200_v1(app)
except Exception:
    pass
# ===================== /VSP_P1_RUN_FILE_ALLOW_WRAP_4XX5XX_TO_200_V1 =====================
""").strip()+"\n"
    s = s.rstrip()+"\n\n"+block2
    print("[OK] injected:", MARK2)
else:
    print("[OK] already present:", MARK2)

W.write_text(s, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] gateway compiles")
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke 1: static js must be JS content-type =="
curl -sS -I "$BASE/static/js/vsp_data_source_lazy_v1.js" | sed -n '1,20p'

echo "== smoke 2: run_file_allow must be HTTP 200 even for bad path =="
curl -sS -o /tmp/_rfwrap.json -w "HTTP=%{http_code}\n" \
  "$BASE/api/vsp/run_file_allow?rid=__BAD__RID__&path=__BAD__PATH__" || true
echo "body:"; head -c 220 /tmp/_rfwrap.json; echo
