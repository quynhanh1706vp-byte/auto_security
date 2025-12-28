#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p3f_${TS}"
echo "[BACKUP] ${W}.bak_p3f_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P3F_BOOT_SILENCE_AND_DS_LITE_SUMMARY_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) Silence import-time stdout/stderr from vsp_demo_app unless VSP_BOOT_LOG=1
# Replace: from vsp_demo_app import app as application  # gunicorn entrypoint
# with guarded redirect block.
imp_pat = re.compile(r'(?m)^\s*from\s+vsp_demo_app\s+import\s+app\s+as\s+application.*$')
m = imp_pat.search(s)
if not m:
    print("[WARN] could not find 'from vsp_demo_app import app as application' line; will NOT patch boot silence")
else:
    guard = r'''# === {MARK}: boot-silence import vsp_demo_app unless VSP_BOOT_LOG=1 ===
import os as _p3f_os, sys as _p3f_sys, contextlib as _p3f_ctx
def _p3f_import_vsp_demo_app():
    # Default: silence noisy import-time prints for commercial UI
    boot_log = (_p3f_os.getenv("VSP_BOOT_LOG","0") or "").strip().lower() in ("1","true","yes","on")
    if boot_log:
        from vsp_demo_app import app as _app
        return _app
    try:
        with open(_p3f_os.devnull, "w") as _dn, _p3f_ctx.redirect_stdout(_dn), _p3f_ctx.redirect_stderr(_dn):
            from vsp_demo_app import app as _app
            return _app
    except Exception:
        # fallback: import normally (better than dead service)
        from vsp_demo_app import app as _app
        return _app

application = _p3f_import_vsp_demo_app()
# === END {MARK} boot-silence ==='''.format(MARK=MARK)

    # Replace single import line with guarded block (preserve indentation at col 0)
    s = s[:m.start()] + guard + s[m.end():]
    print("[OK] boot-silence import patched")

# 2) Add a wrapper middleware AFTER current application exists:
# - Adds summary counts for datasource?mode=dashboard (severity/tool)
# - Supports lite=1 and limit=... to cap findings array
# - Adds alias endpoint /api/vsp/datasource_lite (auto lite=1)
mw = r'''
# === {MARK} ===
import json as _p3f_json
from urllib.parse import parse_qs as _p3f_parse_qs

_P3F_SEV_ORDER = {"CRITICAL":0,"HIGH":1,"MEDIUM":2,"MEDIUM+":2,"LOW":3,"INFO":4,"TRACE":5}

def _p3f_sev_key(item):
    try:
        s = str((item or {}).get("severity","")).upper()
    except Exception:
        s = ""
    return _P3F_SEV_ORDER.get(s, 99)

def _p3f_counts(items):
    sev = {}
    tool = {}
    for it in items or []:
        try:
            s = str((it or {}).get("severity","")).upper() or "INFO"
        except Exception:
            s = "INFO"
        sev[s] = sev.get(s, 0) + 1
        try:
            t = (it or {}).get("tool") or "UNKNOWN"
        except Exception:
            t = "UNKNOWN"
        t = str(t)
        tool[t] = tool.get(t, 0) + 1
    return sev, tool

class _P3FCommercialPerfMiddleware:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        qs = _p3f_parse_qs(environ.get("QUERY_STRING") or "")

        # Alias endpoint: /api/vsp/datasource_lite -> /api/vsp/datasource?mode=dashboard&lite=1
        if path == "/api/vsp/datasource_lite":
            environ = dict(environ)
            environ["PATH_INFO"] = "/api/vsp/datasource"
            # merge existing query with lite=1
            q = environ.get("QUERY_STRING") or ""
            if "lite=" not in q:
                q = (q + "&" if q else "") + "lite=1"
            if "mode=" not in q:
                q = (q + "&" if q else "") + "mode=dashboard"
            environ["QUERY_STRING"] = q
            path = environ["PATH_INFO"]
            qs = _p3f_parse_qs(environ.get("QUERY_STRING") or "")

        # Only post-process dashboard datasource to reduce payload optionally
        if path == "/api/vsp/datasource" and (qs.get("mode") or [""])[0] == "dashboard":
            # Call downstream, capture status+headers+body
            cap_status = {}
            cap_headers = {}
            def _sr(status, headers, exc_info=None):
                cap_status["status"] = status
                cap_headers["headers"] = headers
                # don't call real start_response yet
            body_bytes = b"".join(self.app(environ, _sr))
            status = cap_status.get("status","200 OK")
            headers = cap_headers.get("headers", []) or []

            # Only handle JSON
            ct = ""
            for k,v in headers:
                if str(k).lower() == "content-type":
                    ct = str(v).lower()
                    break
            if "application/json" not in ct:
                start_response(status, headers)
                return [body_bytes]

            try:
                j = _p3f_json.loads(body_bytes.decode("utf-8", errors="replace"))
            except Exception:
                start_response(status, headers)
                return [body_bytes]

            if not isinstance(j, dict):
                start_response(status, headers)
                return [body_bytes]

            findings = j.get("findings") if isinstance(j.get("findings"), list) else []
            total = len(findings)

            # Always add summary (doesn't break UI)
            sev_counts, tool_counts = _p3f_counts(findings)
            j["summary"] = {
                "findings_total": total,
                "severity_counts": sev_counts,
                "tool_counts": tool_counts,
            }

            # Decide whether to trim payload
            env_lite = (os.getenv("VSP_DASH_LITE","0") or "").strip().lower() in ("1","true","yes","on")
            req_lite = (qs.get("lite") or ["0"])[0].strip().lower() in ("1","true","yes","on")
            lite = env_lite or req_lite

            # limit param
            try:
                limit = int((qs.get("limit") or ["800"])[0])
            except Exception:
                limit = 800
            limit = max(0, min(limit, 20000))

            # hard cap env (safety)
            try:
                env_cap = int(os.getenv("VSP_DASH_FINDINGS_MAX","5000"))
            except Exception:
                env_cap = 5000
            env_cap = max(100, min(env_cap, 50000))

            # Apply only when lite OR too large
            if lite or total > env_cap:
                # keep worst severities first
                findings_sorted = sorted(findings, key=_p3f_sev_key)
                trimmed = findings_sorted[: min(limit, len(findings_sorted)) ]
                j["findings"] = trimmed
                j["summary"]["findings_returned"] = len(trimmed)
                j["summary"]["lite"] = True
                j["summary"]["limit"] = limit
                j["summary"]["env_cap"] = env_cap
            else:
                j["summary"]["findings_returned"] = total
                j["summary"]["lite"] = False
                j["summary"]["env_cap"] = env_cap

            out = (_p3f_json.dumps(j, ensure_ascii=False) + "\n").encode("utf-8")
            # rewrite headers content-length
            new_headers = []
            for k,v in headers:
                if str(k).lower() == "content-length":
                    continue
                new_headers.append((k,v))
            new_headers.append(("Content-Length", str(len(out))))
            new_headers.append(("Cache-Control","no-store"))
            start_response(status, new_headers)
            return [out]

        return self.app(environ, start_response)

# Wrap application (chain after existing middleware)
try:
    application = _P3FCommercialPerfMiddleware(application)
except Exception:
    pass
# === END {MARK} ===
'''.format(MARK=MARK).lstrip("\n")

s = s.rstrip() + "\n\n" + mw + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended P3F middleware ->", p)
PY

echo "== [1] import check =="
"$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK')"

echo "== [2] restart =="
sudo systemctl restart "${SVC}"
sleep 0.6
sudo systemctl is-active --quiet "${SVC}" && echo "[OK] service active" || { echo "[ERR] service not active"; sudo systemctl status "${SVC}" --no-pager | sed -n '1,220p'; exit 3; }

echo "== [3] smoke (normal) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
curl -fsS "$BASE/api/vsp/datasource?mode=dashboard&rid=$RID" \
  | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"runs=",len(j.get("runs") or []),"findings=",len(j.get("findings") or []),"total=",((j.get("summary") or {}).get("findings_total")),"lite=",((j.get("summary") or {}).get("lite")) )'

echo "== [4] smoke (lite=1&limit=200) =="
curl -fsS "$BASE/api/vsp/datasource?mode=dashboard&rid=$RID&lite=1&limit=200" \
  | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"findings=",len(j.get("findings") or []),"total=",((j.get("summary") or {}).get("findings_total")),"returned=",((j.get("summary") or {}).get("findings_returned")),"lite=",((j.get("summary") or {}).get("lite")) )'

echo "== [5] smoke alias datasource_lite =="
curl -fsS "$BASE/api/vsp/datasource_lite?rid=$RID&limit=150" \
  | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"findings=",len(j.get("findings") or []),"total=",((j.get("summary") or {}).get("findings_total")),"lite=",((j.get("summary") or {}).get("lite")) )'

echo "[DONE] p3f_boot_silence_and_ds_lite_summary_v1"
