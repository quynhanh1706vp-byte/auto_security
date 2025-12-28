#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# Prefer canonical gateway module
CAND="wsgi_vsp_ui_gateway.py"
if [ -f "$CAND" ]; then
  F="$CAND"
else
  # fallback: find file that contains "wsgi_vsp_ui_gateway" or "application" in ui root
  F="$(grep -RIl --include='*.py' -E 'wsgi_vsp_ui_gateway|application\s*=' . | head -n 1 || true)"
fi

[ -n "${F:-}" ] || { echo "[ERR] cannot locate wsgi gateway python file"; exit 2; }
[ -f "$F" ] || { echo "[ERR] missing file: $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_statusv2_always8_${TS}"
echo "[BACKUP] $F.bak_statusv2_always8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path(r"""%s""")
s = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_WSGI_STATUSV2_ALWAYS8_V1 ==="
if TAG in s:
    print("[OK] patch already present, skip")
    raise SystemExit(0)

# find "application =" assignment (gunicorn uses wsgi_vsp_ui_gateway:application)
m = re.search(r"(?m)^\s*application\s*=\s*.+$", s)
if not m:
    print("[ERR] cannot find 'application =' in", p)
    raise SystemExit(2)

inject = f"""
{TAG}
import json

def _vsp_build_tools_always8_v1(out: dict) -> dict:
    CANON = ["SEMGREP","GITLEAKS","TRIVY","CODEQL","KICS","GRYPE","SYFT","BANDIT"]
    ZERO = {{"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}}

    def norm_counts(c):
        d = dict(ZERO)
        if isinstance(c, dict):
            for k,v in c.items():
                kk = str(k).upper()
                if kk in d:
                    try: d[kk] = int(v)
                    except Exception: d[kk] = 0
        return d

    def mk(tool, has_key=None, total_key=None, verdict_key=None, counts_key=None, reason_missing="missing_fields"):
        hasv = out.get(has_key) if has_key else None
        try: hasv = bool(hasv) if has_key else None
        except Exception: hasv = None

        total = out.get(total_key, 0) if total_key else 0
        verdict = out.get(verdict_key) if verdict_key else None
        counts = norm_counts(out.get(counts_key, {{}})) if counts_key else dict(ZERO)

        if has_key and hasv is False:
            return {{"tool":tool,"status":"NOT_RUN","verdict":"NOT_RUN","total":0,"counts":dict(ZERO),"reason":"has_flag_false"}}

        if verdict is None and (not total) and counts == ZERO:
            return {{"tool":tool,"status":"NOT_RUN","verdict":"NOT_RUN","total":0,"counts":dict(ZERO),"reason":reason_missing}}

        vv = str(verdict).upper() if verdict is not None else "OK"
        try:
            total_i = int(total)
        except Exception:
            total_i = 0
        return {{"tool":tool,"status":vv,"verdict":vv,"total":total_i,"counts":counts}}

    tools = {{}}

    # handle flat status_v2 (your current response keys)
    tools["CODEQL"]   = mk("CODEQL",   "has_codeql",   "codeql_total",   "codeql_verdict",   None)
    tools["GITLEAKS"] = mk("GITLEAKS", "has_gitleaks", "gitleaks_total", "gitleaks_verdict", "gitleaks_counts")
    tools["SEMGREP"]  = mk("SEMGREP",  "has_semgrep",  "semgrep_total",  "semgrep_verdict",  "semgrep_counts")
    tools["TRIVY"]    = mk("TRIVY",    "has_trivy",    "trivy_total",    "trivy_verdict",    "trivy_counts")

    # missing converters -> NOT_RUN (commercial invariant: lane must exist)
    for t in ["KICS","GRYPE","SYFT","BANDIT"]:
        tools[t] = {{"tool":t,"status":"NOT_RUN","verdict":"NOT_RUN","total":0,"counts":dict(ZERO),"reason":"no_converter_yet"}}

    out["tools"] = tools
    out["tools_order"] = CANON

    gs = out.get("run_gate_summary")
    if not isinstance(gs, dict):
        gs = {{}}
    for t in CANON:
        if t not in gs:
            gs[t] = {{"tool":t,"verdict": tools[t].get("verdict","NOT_RUN"), "total": tools[t].get("total",0)}}
    out["run_gate_summary"] = gs
    return out

def _vsp_wrap_statusv2_always8_v1(app):
    def _app(environ, start_response):
        path = environ.get("PATH_INFO","") or ""
        if not path.startswith("/api/vsp/run_status_v2/"):
            return app(environ, start_response)

        captured = {{"status": None, "headers": None, "exc": None}}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = headers
            captured["exc"] = exc_info
            # return write() func (rarely used); ignore
            return lambda x: None

        res_iter = app(environ, _sr)
        try:
            body = b"".join(res_iter or [])
        finally:
            try:
                close = getattr(res_iter, "close", None)
                if callable(close): close()
            except Exception:
                pass

        headers = captured["headers"] or []
        ctype = ""
        for k,v in headers:
            if str(k).lower() == "content-type":
                ctype = str(v)
                break

        if "application/json" not in ctype.lower():
            start_response(captured["status"] or "200 OK", headers, captured["exc"])
            return [body]

        try:
            out = json.loads(body.decode("utf-8", errors="ignore") or "{}")
            if isinstance(out, dict) and (out.get("tools") is None):
                out = _vsp_build_tools_always8_v1(out)
                new_body = json.dumps(out, ensure_ascii=False).encode("utf-8")
                # fix content-length
                new_headers = []
                for k,v in headers:
                    if str(k).lower() == "content-length":
                        continue
                    new_headers.append((k,v))
                new_headers.append(("Content-Length", str(len(new_body))))
                start_response(captured["status"] or "200 OK", new_headers, captured["exc"])
                return [new_body]
        except Exception:
            pass

        start_response(captured["status"] or "200 OK", headers, captured["exc"])
        return [body]
    return _app
"""

# insert helper block BEFORE application assignment, then wrap application right after
ins_pos = m.start()
s2 = s[:ins_pos] + inject + "\n\n" + s[ins_pos:]

# after the first "application =" line, add wrapper line
m2 = re.search(r"(?m)^\s*application\s*=\s*.+$", s2)
wrap_line = "\napplication = _vsp_wrap_statusv2_always8_v1(application)\n"
s2 = s2[:m2.end()] + wrap_line + s2[m2.end():]

p.write_text(s2, encoding="utf-8")
print("[OK] patched", p)
PY
""" % ("$F"))

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile $F"
echo "[DONE] WSGI patch applied to $F"
