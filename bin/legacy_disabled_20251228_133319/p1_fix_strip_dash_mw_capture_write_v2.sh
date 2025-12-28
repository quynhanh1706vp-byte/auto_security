#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need curl

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_strip_dash_inline_fixwrite_${TS}"
echo "[BACKUP] ${GW}.bak_strip_dash_inline_fixwrite_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

BEGIN = r"# === VSP_P1_STRIP_INLINE_DASH_AND_RID_LATEST_WSGIMW_V1 BEGIN ==="
END   = r"# === VSP_P1_STRIP_INLINE_DASH_AND_RID_LATEST_WSGIMW_V1 END ==="

if (BEGIN not in s) or (END not in s):
    print("[ERR] cannot find V1 block markers to replace. abort.")
    raise SystemExit(2)

block = r'''
# === VSP_P1_STRIP_INLINE_DASH_AND_RID_LATEST_WSGIMW_V2 BEGIN ===
# Fix: capture BOTH iterable body and legacy start_response(write) body to avoid empty responses.
try:
    import re as _re
    import json as _json

    class _VspStripInlineDashAndRidLatestMW_V2:
        def __init__(self, app):
            self.app = app

        def __call__(self, environ, start_response):
            path = (environ.get("PATH_INFO") or "")
            captured = {"status": None, "headers": None, "exc": None}
            body_chunks = []

            def _sr(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers or [])
                captured["exc"] = exc_info

                # WSGI legacy: return a write() callable
                def write(data):
                    try:
                        if data:
                            if isinstance(data, str):
                                data = data.encode("utf-8", errors="replace")
                            body_chunks.append(data)
                    except Exception:
                        pass
                return write

            try:
                it = self.app(environ, _sr)
                for b in it:
                    if not b:
                        continue
                    if isinstance(b, str):
                        b = b.encode("utf-8", errors="replace")
                    body_chunks.append(b)
                if hasattr(it, "close"):
                    it.close()
            except Exception:
                return self.app(environ, start_response)

            status = captured["status"] or "200 OK"
            headers = captured["headers"] or []
            body = b"".join(body_chunks)

            def _get_header(name: str):
                ln = name.lower()
                for k, v in headers:
                    if str(k).lower() == ln:
                        return v
                return None

            ct = (_get_header("Content-Type") or "").lower()

            # A) Schema compat: ensure rid_latest on /api/vsp/runs JSON
            if path == "/api/vsp/runs" and ("application/json" in ct or ct.endswith("+json") or ct == ""):
                # ct can be empty if upstream MW forgets it; still attempt JSON parse guardedly
                try:
                    txt = body.decode("utf-8", errors="replace").strip()
                    if txt.startswith("{") and txt.endswith("}"):
                        j = _json.loads(txt)
                        if isinstance(j, dict) and ("rid_latest" not in j):
                            items = j.get("items") or []
                            if isinstance(items, list) and items:
                                rid0 = (items[0] or {}).get("run_id")
                                if rid0:
                                    j["rid_latest"] = rid0
                                    body = _json.dumps(j, ensure_ascii=False).encode("utf-8")
                                    # set ct if missing
                                    if not any(str(k).lower()=="content-type" for k,v in headers):
                                        headers.append(("Content-Type","application/json; charset=utf-8"))
                except Exception:
                    pass

            # B) Strip injected inline dash scripts on /vsp5 HTML (outermost)
            if path == "/vsp5" and ("text/html" in ct or ct == ""):
                try:
                    html = body.decode("utf-8", errors="replace")

                    def _kill_script(m):
                        whole = m.group(0)
                        inner = m.group(2) or ""
                        sigs = [
                            "rid_latest", "vsp_live_rid", "vsp_rid_latest_badge",
                            "containers/rid", "Chart/container", "[VSP][DASH]",
                            "gave up", "container missing"
                        ]
                        if any(s in inner for s in sigs):
                            return ""
                        return whole

                    html2 = _re.sub(r"(<script[^>]*>)(.*?)(</script>)", _kill_script, html, flags=_re.S|_re.I)
                    if html2 != html:
                        body = html2.encode("utf-8")
                        headers = [(k, v) for (k, v) in headers if str(k).lower() not in ("content-length", "cache-control")]
                        headers.append(("Cache-Control", "no-store"))
                except Exception:
                    pass

            # normalize Content-Length
            headers = [(k, v) for (k, v) in headers if str(k).lower() != "content-length"]
            headers.append(("Content-Length", str(len(body))))

            start_response(status, headers, captured["exc"])
            return [body]

    # Replace wsgi_app with V2 (outermost)
    try:
        application.wsgi_app = _VspStripInlineDashAndRidLatestMW_V2(application.wsgi_app)
    except Exception:
        pass

except Exception:
    pass
# === VSP_P1_STRIP_INLINE_DASH_AND_RID_LATEST_WSGIMW_V2 END ===
'''

# Replace V1 block entirely
s2 = re.sub(
    re.escape(BEGIN) + r".*?" + re.escape(END),
    block,
    s,
    flags=re.S
)
p.write_text(s2, encoding="utf-8")
print("[OK] replaced V1 -> V2 MW block")
PY

python3 -m py_compile "$GW" && echo "[OK] py_compile OK"

echo "== restart clean :8910 (nohup only) =="
rm -f /tmp/vsp_ui_8910.lock || true
PID="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1)"
[ -n "${PID:-}" ] && kill -9 "$PID" || true

: > out_ci/ui_8910.boot.log || true
: > out_ci/ui_8910.error.log || true
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

sleep 1.2

echo "== verify /api/vsp/runs JSON + rid_latest =="
BASE=http://127.0.0.1:8910
curl -sS -D - "$BASE/api/vsp/runs?limit=1" | sed -n '1,18p'
curl -sS "$BASE/api/vsp/runs?limit=1" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("rid_latest =", j.get("rid_latest"))
print("items0.run_id =", (j.get("items") or [{}])[0].get("run_id"))
PY
