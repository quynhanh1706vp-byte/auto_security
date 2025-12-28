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
cp -f "$W" "${W}.bak_runfilealways200_${TS}"
echo "[BACKUP] ${W}.bak_runfilealways200_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, textwrap

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RUN_FILE_ALLOW_ALWAYS200_ON_5XX_V1"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_RUN_FILE_ALLOW_ALWAYS200_ON_5XX_V1 =====================
def _vsp_mw_run_file_allow_always200_on_5xx_v1(app):
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

        # If not 5xx, pass through as-is
        if code < 500:
            start_response(status, captured["headers"] or [])
            return resp_iter

        # Buffer body (best-effort) then replace with JSON 200
        try:
            _body = b"".join(resp_iter)
        except Exception:
            _body = b""
        finally:
            try:
                close = getattr(resp_iter, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        payload = {
            "ok": False,
            "err": "upstream_5xx_wrapped",
            "upstream_status": status,
            "note": "Gateway wrapped 5xx into HTTP 200 for commercial UI stability."
        }
        out = json.dumps(payload, ensure_ascii=False).encode("utf-8")

        headers = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Cache-Control", "no-store"),
            ("X-VSP-WRAP", "run_file_allow_5xx_to_200"),
            ("Content-Length", str(len(out))),
        ]
        start_response("200 OK", headers)
        return [out]

    return middleware

# wrap callable(s)
try:
    if "application" in globals() and callable(globals().get("application")):
        application = _vsp_mw_run_file_allow_always200_on_5xx_v1(application)
except Exception:
    pass
try:
    if "app" in globals() and callable(globals().get("app")):
        app = _vsp_mw_run_file_allow_always200_on_5xx_v1(app)
except Exception:
    pass
# ===================== /VSP_P1_RUN_FILE_ALLOW_ALWAYS200_ON_5XX_V1 =====================
""").strip() + "\n"

W.write_text(s.rstrip() + "\n\n" + block, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] patched + compiled:", MARK)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: run_file_allow must never 5xx (expect 200) =="
curl -sS -o /tmp/_rf.json -w "HTTP=%{http_code}\n" \
  "$BASE/api/vsp/run_file_allow?rid=__BAD__RID__&path=__BAD__PATH__" || true
echo "body:"; head -c 180 /tmp/_rf.json; echo
