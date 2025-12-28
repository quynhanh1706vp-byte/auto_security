#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runsjson_${TS}"
echo "[BACKUP] ${F}.bak_runsjson_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_WSGI_RUNS_JSON_FALLBACK_V1"
if MARK in s:
    print("[OK] already injected:", MARK)
    raise SystemExit(0)

inject = r'''
# === VSP_P1_WSGI_RUNS_JSON_FALLBACK_V1 ===
def _vsp_runs_json_fallback_wsgi(app):
    """
    WSGI-level fallback for /api/vsp/runs:
    - If upstream returns 500/HTML/non-JSON OR raises, return JSON computed from OUT_ROOT.
    - Keeps UI usable even when Flask route breaks.
    """
    import json, os, time
    from urllib.parse import parse_qs, quote
    from pathlib import Path

    OUT_ROOT = Path("/home/test/Data/SECURITY_BUNDLE/out")

    def _list_runs(limit=50):
        items=[]
        if OUT_ROOT.exists():
            for d in OUT_ROOT.iterdir():
                if not d.is_dir():
                    continue
                try:
                    mtime = int(d.stat().st_mtime)
                except Exception:
                    mtime = 0
                rd = d / "reports"
                def ex(rel):
                    try:
                        return (rd / rel).exists()
                    except Exception:
                        return False
                rid = d.name
                items.append({
                    "run_id": rid,
                    "path": str(d),
                    "mtime": mtime,
                    "mtime_h": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(mtime)) if mtime else "n/a",
                    "has": {
                        "html": ex("index.html"),
                        "summary": ex("run_gate_summary.json"),
                        "json": ex("findings_unified.json"),
                        "csv": ex("findings_unified.csv"),
                        "sarif": ex("findings_unified.sarif") or ex("findings_unified.sarif.json"),
                        "txt": ex("SUMMARY.txt"),
                        "sha": ex("SHA256SUMS.txt"),
                        "html_path": f"/api/vsp/run_file?rid={quote(rid)}&name=reports%2Findex.html",
                        "summary_path": f"/api/vsp/run_file?rid={quote(rid)}&name=reports%2Frun_gate_summary.json",
                        "json_path": f"/api/vsp/run_file?rid={quote(rid)}&name=reports%2Ffindings_unified.json",
                        "txt_path": f"/api/vsp/run_file?rid={quote(rid)}&name=reports%2FSUMMARY.txt",
                        "sha_path": f"/api/vsp/run_file?rid={quote(rid)}&name=reports%2FSHA256SUMS.txt",
                    }
                })
        items.sort(key=lambda x: x.get("mtime",0), reverse=True)
        return items[:max(1,int(limit))]

    def _json_response(start_response, payload, code="200 OK"):
        body = (json.dumps(payload, ensure_ascii=False)).encode("utf-8")
        start_response(code, [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("Content-Length", str(len(body))),
            ("X-VSP-RUNS-FALLBACK", MARK),
        ])
        return [body]

    def _is_json_bytes(b: bytes) -> bool:
        if not b:
            return False
        b2 = b.lstrip()
        return b2.startswith(b"{") or b2.startswith(b"[")

    def wsgi(environ, start_response):
        path = environ.get("PATH_INFO","") or ""
        method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()

        if path == "/api/vsp/runs" and method == "GET":
            try:
                qs = parse_qs(environ.get("QUERY_STRING","") or "")
                limit = (qs.get("limit") or ["50"])[0]
            except Exception:
                limit = "50"

            # try upstream first
            try:
                captured = {}
                chunks = []
                def _sr(status, headers, exc_info=None):
                    captured["status"]=status
                    captured["headers"]=headers
                it = app(environ, _sr)
                for c in it:
                    chunks.append(c)
                body = b"".join(chunks)

                st = captured.get("status","500").split()[0]
                # if upstream OK and JSON => return as-is
                if st.startswith("2") and _is_json_bytes(body):
                    start_response(captured.get("status","200 OK"), captured.get("headers",[]))
                    return [body]
            except Exception:
                pass

            # fallback JSON
            items = _list_runs(limit=limit)
            payload = {"ok": True, "who": MARK, "root": str(OUT_ROOT), "items": items, "items_len": len(items)}
            return _json_response(start_response, payload, "200 OK")

        return app(environ, start_response)

    return wsgi
# === /VSP_P1_WSGI_RUNS_JSON_FALLBACK_V1 ===
'''

# Append near end + wrap application
s2 = s + "\n" + inject + "\n"

# Wrap at bottom in safest way
wrap = r'''
# === VSP_P1_WSGI_RUNS_JSON_FALLBACK_V1_APPLY ===
try:
    # prefer existing "application" if present
    if "application" in globals():
        application = _vsp_runs_json_fallback_wsgi(application)
    elif "app" in globals():
        application = _vsp_runs_json_fallback_wsgi(app)
except Exception:
    pass
# === /VSP_P1_WSGI_RUNS_JSON_FALLBACK_V1_APPLY ===
'''
s2 += wrap

p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK: wsgi_vsp_ui_gateway.py"

sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== smoke: /api/vsp/runs must be JSON now =="
curl -sS -i http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -n 25
