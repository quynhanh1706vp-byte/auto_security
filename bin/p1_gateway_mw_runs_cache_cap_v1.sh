#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_mw_${TS}"
echo "[BACKUP] ${F}.bak_runs_mw_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_RUNS_CACHE_MW_V1"
if MARK in s:
    print("[OK] already injected")
    raise SystemExit(0)

# find LAST assignment to "application = ..."
m=list(re.finditer(r'(?m)^\s*application\s*=\s*(.+?)\s*$', s))
if not m:
    print("[ERR] cannot find 'application = ...' in gateway")
    raise SystemExit(2)

last=m[-1]
rhs=last.group(1).strip()

inject=f'''
# {MARK}
import json as _json, os as _os, time as _time
from pathlib import Path as _Path

class _VspRunsCacheMW:
    """
    Intercept /api/vsp/runs and serve cheap cached JSON to avoid heavy scans / crashes.
    - TTL cache (default 2s)
    - limit cap (default 10)
    - never reads large JSON files; only checks existence
    """
    def __init__(self, app, ttl=2.0, limit_cap=10):
        self.app = app
        self.ttl = float(_os.environ.get("VSP_RUNS_CACHE_TTL", ttl))
        self.limit_cap = int(_os.environ.get("VSP_RUNS_LIMIT_CAP", limit_cap))
        self._cache = {{ "ts": 0.0, "key": "", "payload": None }}

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path != "/api/vsp/runs":
            return self.app(environ, start_response)

        # parse ?limit=
        qs = (environ.get("QUERY_STRING") or "")
        limit = 5
        for part in qs.split("&"):
            if part.startswith("limit="):
                try: limit = int(part.split("=",1)[1] or "5")
                except Exception: limit = 5
        if limit <= 0: limit = 5
        if limit > self.limit_cap: limit = self.limit_cap

        root_env = (_os.environ.get("VSP_RUNS_ROOT","") or "").strip()
        roots = []
        if root_env:
            roots.append(_Path(root_env))
        roots += [_Path("/home/test/Data/SECURITY_BUNDLE/out"), _Path("/home/test/Data/SECURITY_BUNDLE/out_ci")]

        key = "|".join([str(r) for r in roots]) + f"|limit={limit}"
        now = _time.time()
        c = self._cache
        if c["payload"] is not None and c["key"] == key and (now - c["ts"]) < self.ttl:
            payload = c["payload"]
        else:
            items = []
            seen=set()
            for base in roots:
                try:
                    if not base.is_dir(): 
                        continue
                    for d in base.iterdir():
                        if not d.is_dir(): 
                            continue
                        rid = d.name
                        if rid in seen:
                            continue
                        seen.add(rid)

                        reports = d / "reports"
                        # existence flags (cheap)
                        has_html = (reports / "index.html").is_file()
                        has_summary = (reports / "run_gate_summary.json").is_file()
                        has_json = (reports / "findings_unified.json").is_file()
                        has_csv = (reports / "findings_unified.csv").is_file()
                        has_txt = (reports / "SUMMARY.txt").is_file()
                        has_sha = (reports / "SHA256SUMS.txt").is_file()

                        item = {{
                            "run_id": rid,
                            "run_dir_resolved": str(d),
                            "has": {{
                                "html": bool(has_html),
                                "summary": bool(has_summary),
                                "json": bool(has_json),
                                "csv": bool(has_csv),
                                "sarif": False,
                                "txt": bool(has_txt),
                                "sha": bool(has_sha),
                            }}
                        }}
                        if has_html:
                            item["has"]["html_path"] = f"/api/vsp/run_file?rid={{rid}}&name=reports%2Findex.html"
                        if has_json:
                            item["has"]["json_path"] = f"/api/vsp/run_file?rid={{rid}}&name=reports%2Ffindings_unified.json"
                        if has_summary:
                            item["has"]["summary_path"] = f"/api/vsp/run_file?rid={{rid}}&name=reports%2Frun_gate_summary.json"
                        if has_txt:
                            item["has"]["txt_path"] = f"/api/vsp/run_file?rid={{rid}}&name=reports%2FSUMMARY.txt"
                        if has_sha:
                            item["has"]["sha_path"] = f"/api/vsp/run_file?rid={{rid}}&name=reports%2FSHA256SUMS.txt"

                        try:
                            item["_mtime"] = d.stat().st_mtime
                        except Exception:
                            item["_mtime"] = 0
                        items.append(item)
                except Exception:
                    continue

            items.sort(key=lambda x: x.get("_mtime", 0), reverse=True)
            for it in items:
                it.pop("_mtime", None)

            payload = {{ "items": items[:limit], "ok": True, "limit": limit }}
            c["ts"], c["key"], c["payload"] = now, key, payload

        body = _json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers = [("Content-Type","application/json; charset=utf-8"), ("Content-Length", str(len(body))), ("Cache-Control","no-store")]
        start_response("200 OK", headers)
        return [body]
# /{MARK}
'''

# Replace last "application = RHS" with wrapper
replacement = f'''
{inject}

_VSP_APP_INNER = {rhs}
application = _VspRunsCacheMW(_VSP_APP_INNER)
'''.strip("\n")

s2 = s[:last.start()] + replacement + "\n" + s[last.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] injected runs cache middleware:", MARK)
PY

echo "== GATE: py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
