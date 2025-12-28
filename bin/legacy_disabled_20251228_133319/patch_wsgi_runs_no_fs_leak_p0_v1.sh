#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_nofs_${TS}"
echo "[BACKUP] ${F}.bak_runs_nofs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_RUNS_NO_FS_LEAK_MW_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# append near end (after application is defined)
block = r'''
# {MARK}
# Rewrite /api/vsp/runs payload: never expose filesystem paths; provide /api/vsp/run_file URLs instead.
import json as _json
from urllib.parse import urlencode as _urlencode

class _VspRunsNoFsLeakMW:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO","") or ""
        if path != "/api/vsp/runs":
            return self.app(environ, start_response)

        captured = {"status": None, "headers": None}
        body_chunks = []

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers)
            # delay sending headers until we possibly rewrite body
            return body_chunks.append

        it = self.app(environ, _sr)

        try:
            for c in it:
                if c:
                    body_chunks.append(c)
        finally:
            try:
                close = getattr(it, "close", None)
                if callable(close): close()
            except Exception:
                pass

        raw = b"".join([c if isinstance(c,(bytes,bytearray)) else str(c).encode("utf-8","replace") for c in body_chunks])
        try:
            obj = _json.loads(raw.decode("utf-8","replace"))
        except Exception:
            # fall back: send original
            headers = captured["headers"] or []
            start_response(captured["status"] or "200 OK", headers)
            return [raw]

        def run_file_url(rid, name):
            qs = _urlencode({"rid": rid, "name": name})
            return "/api/vsp/run_file?" + qs

        items = obj.get("items") if isinstance(obj, dict) else None
        if isinstance(items, list):
            for it in items:
                if not isinstance(it, dict): 
                    continue
                rid = it.get("run_id") or it.get("rid")
                has = it.get("has")
                if not rid or not isinstance(has, dict):
                    continue
                # normalize paths to URLs
                # html
                if has.get("html") is True:
                    has["html_path"] = run_file_url(rid, "reports/index.html")
                elif "html_path" in has and isinstance(has["html_path"], str) and has["html_path"].startswith("/home/"):
                    # if backend leaked FS path, convert to URL and set html true
                    has["html"] = True
                    has["html_path"] = run_file_url(rid, "reports/index.html")
                # json (standardize to reports/findings_unified.json)
                if "json_path" in has:
                    has["json_path"] = run_file_url(rid, "reports/findings_unified.json")
                if has.get("json") is True:
                    has["json_path"] = run_file_url(rid, "reports/findings_unified.json")
                # summary
                if "summary_path" in has:
                    has["summary_path"] = run_file_url(rid, "reports/run_gate_summary.json")
                if has.get("summary") is True:
                    has["summary_path"] = run_file_url(rid, "reports/run_gate_summary.json")

                # Optional: offer txt path in reports (more likely whitelisted)
                has["txt_path"] = run_file_url(rid, "reports/SUMMARY.txt")

        out = _json.dumps(obj, ensure_ascii=False).encode("utf-8")
        headers = [(k,v) for (k,v) in (captured["headers"] or []) if k.lower() != "content-length"]
        headers.append(("Content-Length", str(len(out))))
        start_response(captured["status"] or "200 OK", headers)
        return [out]

application = _VspRunsNoFsLeakMW(application)
'''.replace("{MARK}", MARK)

p.write_text(s + "\n" + block + "\n", encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

sudo systemctl restart vsp-ui-8910.service
sleep 0.6
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | jq '.items[0].has | {html,html_path,json,json_path,summary,summary_path,txt_path}'
