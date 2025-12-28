#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_statusmw_${TS}" && echo "[BACKUP] $F.bak_statusmw_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="# === VSP_WSGI_STATUS_CONTRACT_MW_P1_V1_BEGIN ==="
END  ="# === VSP_WSGI_STATUS_CONTRACT_MW_P1_V1_END ==="

block = r'''
{BEGIN}
import os, json, re
from pathlib import Path

def _vsp_read_json(fp):
    try:
        with open(fp, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def _vsp_findings_total(run_dir: str):
    if not run_dir:
        return None
    for fn in ("findings_unified.json","reports/findings_unified.json","findings_unified.sarif","findings_unified.sarif.json"):
        fp=os.path.join(run_dir, fn)
        if os.path.isfile(fp):
            j=_vsp_read_json(fp)
            if isinstance(j, dict):
                if isinstance(j.get("total"), int):
                    return j["total"]
                items=j.get("items")
                if isinstance(items, list):
                    return len(items)
    fp=os.path.join(run_dir,"summary_unified.json")
    j=_vsp_read_json(fp) if os.path.isfile(fp) else None
    if isinstance(j, dict):
        t=j.get("total") or j.get("total_findings")
        if isinstance(t, int):
            return t
    return None

def _vsp_degraded_info(run_dir: str):
    if not run_dir:
        return (None, None)
    # prefer runner.log
    cand = os.path.join(run_dir,"runner.log")
    if not os.path.isfile(cand):
        # fallbacks
        for alt in ("kics/kics.log","codeql/codeql.log","trivy/trivy.log"):
            ap=os.path.join(run_dir,alt)
            if os.path.isfile(ap):
                cand=ap; break
        else:
            return (None, None)
    try:
        txt=Path(cand).read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return (None, None)

    tools = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"]
    degraded=set()
    for t in tools:
        pats = [
            fr"VSP_{t}_TIMEOUT_DEGRADE",
            fr"\[{t}\].*DEGRADED",
            fr"{t}.*timeout.*degrad",
            fr"{t}.*missing.*degrad",
        ]
        for pat in pats:
            if re.search(pat, txt, flags=re.I):
                degraded.add(t)
                break
    n=len(degraded)
    return (n, n>0)

class VSPStatusContractMWP1V1:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO","") or ""
        if not path.startswith("/api/vsp/run_status_v2/"):
            return self.app(environ, start_response)

        captured = {"status":"200 OK","headers":[],"exc":None}

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = headers or []
            captured["exc"] = exc_info
            # delay calling start_response

        it = self.app(environ, _sr)
        try:
            body = b"".join(it)
        finally:
            try:
                it.close()
            except Exception:
                pass

        headers = captured["headers"]
        ctype = ""
        for k,v in headers:
            if str(k).lower() == "content-type":
                ctype = str(v)
                break

        # only postprocess JSON
        if "application/json" not in ctype.lower():
            start_response(captured["status"], headers, captured["exc"])
            return [body]

        try:
            obj = json.loads(body.decode("utf-8","ignore"))
        except Exception:
            start_response(captured["status"], headers, captured["exc"])
            return [body]

        if not isinstance(obj, dict):
            start_response(captured["status"], headers, captured["exc"])
            return [body]

        rid = path.rsplit("/",1)[-1]
        obj["run_id"] = obj.get("run_id") or rid

        run_dir = obj.get("ci_run_dir") or obj.get("ci")
        if run_dir and os.path.isdir(run_dir):
            t = _vsp_findings_total(run_dir)
            if isinstance(t, int):
                obj["total_findings"] = t
                obj["has_findings"] = True if t > 0 else False

            dn, da = _vsp_degraded_info(run_dir)
            if isinstance(dn, int):
                obj["degraded_n"] = dn
            if isinstance(da, bool):
                obj["degraded_any"] = da

        obj.setdefault("ok", True)

        out = json.dumps(obj, ensure_ascii=False).encode("utf-8")

        # fix content-length
        new_headers=[]
        for k,v in headers:
            if str(k).lower() == "content-length":
                continue
            new_headers.append((k,v))
        new_headers.append(("Content-Length", str(len(out))))

        start_response(captured["status"], new_headers, captured["exc"])
        return [out]

# wrap if possible
try:
    application = VSPStatusContractMWP1V1(application)
except Exception:
    pass
{END}
'''.replace("{BEGIN}", BEGIN).replace("{END}", END)

if BEGIN in s and END in s:
    s = re.sub(re.escape(BEGIN)+r".*?"+re.escape(END), block, s, flags=re.S)
else:
    s = s.rstrip() + "\n\n" + block + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] injected WSGI status contract middleware")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile OK => $F"
