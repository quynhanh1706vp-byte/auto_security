#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_contract_wsgimw_${TS}"
echo "[BACKUP] ${F}.bak_runs_contract_wsgimw_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RUNS_CONTRACT_WSGIMW_V1"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

block = f"""
# ==== {MARK} ====
# P1 commercial: WSGI middleware that rewrites /api/vsp/runs response at the LAST layer
# (avoids being overridden by other after_request/middleware).
def _vsp__parse_qs_limit(environ, default=50, hard_cap=120):
    try:
        qs = environ.get("QUERY_STRING") or ""
        for part in qs.split("&"):
            if part.startswith("limit="):
                v = part.split("=",1)[1]
                n = int(v.strip() or default)
                return max(1, min(n, hard_cap))
    except Exception:
        pass
    return max(1, min(default, hard_cap))

def _vsp__list_latest_runs_cached(roots, limit, ttl=2):
    # cache in function attribute
    import time, os
    from pathlib import Path as _P
    now = time.time()
    cache = getattr(_vsp__list_latest_runs_cached, "_cache", None) or {{}}
    key = "|".join(roots) + f":{limit}"
    ent = cache.get(key)
    if ent and (now - ent["ts"] <= ttl):
        return ent["items"]

    runs = []
    for r in roots:
        try:
            rp = _P(r)
            if not rp.exists():
                continue
            # scandir is faster than glob for many dirs
            with os.scandir(rp) as it:
                for de in it:
                    if not de.is_dir():
                        continue
                    nm = de.name
                    if nm.startswith("RUN_") or "_RUN_" in nm:
                        try:
                            st = de.stat()
                            runs.append((st.st_mtime, _P(de.path)))
                        except Exception:
                            pass
        except Exception:
            continue

    runs.sort(key=lambda x: x[0], reverse=True)
    take = min(len(runs), limit)
    items=[]
    for _, d in runs[:take]:
        rid = d.name
        rep = d / "reports"
        has = {{
            "csv": (rep / "findings_unified.csv").exists(),
            "html": (rep / "checkmarx_like.html").exists(),
            "json": (rep / "findings_unified.json").exists() or (d / "findings_unified.json").exists(),
            "sarif": (rep / "findings_unified.sarif").exists() or (d / "findings_unified.sarif").exists(),
            "summary": (rep / "run_gate_summary.json").exists() or (d / "run_gate_summary.json").exists(),
        }}
        items.append({{"run_id": rid, "has": has}})
    cache[key] = {{"ts": now, "items": items}}
    setattr(_vsp__list_latest_runs_cached, "_cache", cache)
    return items

class _VSPRunsContractWSGIMW:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO") or ""
        if path != "/api/vsp/runs":
            return self.app(environ, start_response)

        captured = {{"status": None, "headers": None}}

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            # do NOT call downstream start_response yet
            return None

        body_iter = self.app(environ, _sr)
        # Join body (runs payload is small); if anything fails, fallback to raw.
        try:
            body = b"".join(body_iter)
        except Exception:
            # fallback streaming
            return self.app(environ, start_response)

        status = captured["status"] or "200 OK"
        headers = captured["headers"] or []
        # only modify 200 + json
        try:
            code = int(status.split()[0])
        except Exception:
            code = 200
        ct = ""
        for k,v in headers:
            if k.lower() == "content-type":
                ct = v
                break
        if code != 200 or ("json" not in (ct or "")):
            start_response(status, headers)
            return [body]

        # rewrite JSON
        try:
            import json, os
            data = json.loads(body.decode("utf-8","replace"))
            if not (isinstance(data, dict) and data.get("ok") is True and isinstance(data.get("items"), list)):
                start_response(status, headers)
                return [body]

            lim_eff = _vsp__parse_qs_limit(environ, default=int(data.get("limit") or 50))
            data["limit"] = lim_eff

            roots = []
            env_roots = (os.environ.get("VSP_RUNS_ROOTS") or "").strip()
            if env_roots:
                roots = [x.strip() for x in env_roots.split(":") if x.strip()]
            else:
                roots = ["/home/test/Data/SECURITY_BUNDLE/out", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"]
            data["roots_used"] = roots

            items = data.get("items") or []
            if not items:
                items = _vsp__list_latest_runs_cached(roots, lim_eff, ttl=int(os.environ.get("VSP_RUNS_CACHE_TTL","2")))
                data["items"] = items

            rid_latest = ""
            if items:
                try:
                    rid_latest = (items[0].get("run_id") or items[0].get("rid") or "").strip()
                except Exception:
                    rid_latest = ""
            data["rid_latest"] = rid_latest

            try:
                data["cache_ttl"] = int(os.environ.get("VSP_RUNS_CACHE_TTL","2"))
            except Exception:
                data["cache_ttl"] = 2

            try:
                scanned = int(data.get("_scanned") or 0)
            except Exception:
                scanned = 0
            scan_cap = int(os.environ.get("VSP_RUNS_SCAN_CAP","500"))
            data["scan_cap"] = scan_cap
            data["scan_cap_hit"] = bool(scanned >= scan_cap)

            out = json.dumps(data, ensure_ascii=False).encode("utf-8")

            # rebuild headers
            new_headers=[]
            for k,v in headers:
                kl=k.lower()
                if kl in ("content-length",):
                    continue
                new_headers.append((k,v))
            new_headers.append(("Content-Length", str(len(out))))
            new_headers.append(("X-VSP-RUNS-CONTRACT", "P1_WSGI_V1"))

            start_response(status, new_headers)
            return [out]
        except Exception:
            start_response(status, headers)
            return [body]

# wrap only once
try:
    if "application" in globals() and not getattr(application, "__vsp_runs_contract_wrapped__", False):
        application = _VSPRunsContractWSGIMW(application)
        try:
            application.__vsp_runs_contract_wrapped__ = True
        except Exception:
            pass
except Exception:
    pass
# ==== /{MARK} ====
"""

p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh

echo "== diag =="
bin/p1_diag_runs_contract_v1.sh || true

echo "== selfcheck =="
bin/p0_commercial_selfcheck_ui_v1.sh || true
