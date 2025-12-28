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

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_RUNS_CACHE_MW_V2"
if MARK in s:
    print("[OK] already injected:", MARK)
    raise SystemExit(0)

m = list(re.finditer(r'(?m)^\s*application\s*=\s*(.+?)\s*$', s))
if not m:
    print("[ERR] cannot find application = ...")
    raise SystemExit(2)

last = m[-1]
rhs = last.group(1).strip()

inject = r'''
# VSP_P1_RUNS_CACHE_MW_V2
import json as _json, os as _os, time as _time, re as _re
from pathlib import Path as _Path

class _VspRunsCacheMW:
    def __init__(self, app):
        self.app = app
        self.ttl = float(_os.environ.get("VSP_RUNS_CACHE_TTL", "3"))
        self.limit_cap = int(_os.environ.get("VSP_RUNS_LIMIT_CAP", "10"))
        self.scan_cap = int(_os.environ.get("VSP_RUNS_SCAN_CAP", "500"))
        self._cache = {"ts": 0.0, "key": "", "payload": None}
        self._run_re = _re.compile(_os.environ.get("VSP_RUNS_DIR_REGEX", r"^(RUN_|AATE_|VSP_|btl).*"))

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path != "/api/vsp/runs":
            return self.app(environ, start_response)

        qs = (environ.get("QUERY_STRING") or "")
        limit = 5
        for part in qs.split("&"):
            if part.startswith("limit="):
                try: limit = int(part.split("=",1)[1] or "5")
                except Exception: limit = 5
        if limit <= 0: limit = 5
        if limit > self.limit_cap: limit = self.limit_cap

        roots = [
            _Path(_os.environ.get("VSP_RUNS_ROOT","") or "").expanduser(),
            _Path("/home/test/Data/SECURITY_BUNDLE/out"),
            _Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        ]
        roots = [r for r in roots if str(r).strip() and r.is_dir()]

        key = "|".join(map(str,roots)) + f"|limit={limit}"
        now = _time.time()
        c = self._cache

        if c["payload"] is not None and c["key"] == key and (now - c["ts"]) < self.ttl:
            payload = c["payload"]
        else:
            items, seen, scanned = [], set(), 0
            for base in roots:
                for d in base.iterdir():
                    if scanned >= self.scan_cap: break
                    scanned += 1
                    if not d.is_dir(): continue
                    rid = d.name
                    if rid in seen: continue
                    if not self._run_re.match(rid): continue
                    seen.add(rid)

                    reports = d / "reports"
                    item = {
                        "run_id": rid,
                        "run_dir_resolved": str(d),
                        "has": {
                            "html": (reports/"index.html").is_file(),
                            "summary": (reports/"run_gate_summary.json").is_file(),
                            "json": (reports/"findings_unified.json").is_file(),
                            "csv": (reports/"findings_unified.csv").is_file(),
                            "sarif": False,
                        }
                    }
                    try: item["_mtime"] = d.stat().st_mtime
                    except Exception: item["_mtime"] = 0
                    items.append(item)

            items.sort(key=lambda x: x.get("_mtime",0), reverse=True)
            for it in items: it.pop("_mtime", None)
            payload = {"ok": True, "limit": limit, "_scanned": scanned, "items": items[:limit]}
            c["ts"], c["key"], c["payload"] = now, key, payload

        body = _json.dumps(payload, ensure_ascii=False).encode("utf-8")
        start_response("200 OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("Cache-Control","no-store"),
        ])
        return [body]
# /VSP_P1_RUNS_CACHE_MW_V2
'''.strip("\n")

replacement = "\n".join([
    inject,
    "",
    "_VSP_APP_INNER = " + rhs,
    "application = _VspRunsCacheMW(_VSP_APP_INNER)",
    ""
])

s2 = s[:last.start()] + replacement + s[last.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
