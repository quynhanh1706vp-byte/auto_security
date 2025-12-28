#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_findprev_wsgih_${TS}"
echo "[BACKUP] $F.bak_findprev_wsgih_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "VSP_WSGI_FINDINGS_PREVIEW_HANDLER_V2"
if TAG in t:
    print("[OK] handler already installed, skip")
    raise SystemExit(0)

BLOCK = r'''

# === VSP_WSGI_FINDINGS_PREVIEW_HANDLER_V2 ===
def _vsp_wsgi_findings_preview_v2(app):
    if getattr(app, "_vsp_wrapped_findprev_v2", False):
        return app
    setattr(app, "_vsp_wrapped_findprev_v2", True)

    import json, csv
    from pathlib import Path
    from urllib.parse import parse_qs

    # reuse resolver if present (export_v3 uses it)
    _resolve = globals().get("_vsp_resolve_ci_run_dir", None)
    if _resolve is None:
        def _resolve(rid: str):
            key = (rid or "").strip()
            if key.startswith("RUN_"):
                key = key[len("RUN_"):]
            bases = [
                "/home/test/Data/SECURITY-10-10-v4/out_ci",
                "/home/test/Data/SECURITY_BUNDLE/out",
                "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
            ]
            for b in bases:
                d = Path(b) / key
                if d.is_dir():
                    return d
            return None

    def _pick_fields(rec: dict):
        return {
            "severity": rec.get("severity") or rec.get("sev") or rec.get("level") or "",
            "tool": rec.get("tool") or rec.get("source") or "",
            "rule_id": rec.get("rule_id") or rec.get("check_id") or rec.get("id") or "",
            "title": rec.get("title") or rec.get("message") or rec.get("name") or "",
            "file": rec.get("file") or rec.get("path") or rec.get("filename") or "",
            "line": rec.get("line") or rec.get("start_line") or rec.get("startLine") or "",
            "cwe": rec.get("cwe") or rec.get("cwe_id") or "",
        }

    def _load_json_findings(fp: Path):
        obj = json.loads(fp.read_text(encoding="utf-8", errors="ignore"))
        if isinstance(obj, dict):
            for k in ("findings","items","results","data"):
                if k in obj and isinstance(obj[k], list):
                    return obj[k]
            return [obj]
        if isinstance(obj, list):
            return obj
        return []

    def _load_csv_findings(fp: Path):
        rows = []
        with fp.open("r", encoding="utf-8", errors="ignore", newline="") as f:
            r = csv.DictReader(f)
            for row in r:
                rows.append(row)
        return rows

    def _match(rec: dict, sevs:set, tools:set, search:str):
        s = (search or "").lower().strip()
        if sevs:
            sev = str(rec.get("severity","")).upper()
            if sev not in sevs:
                return False
        if tools:
            tool = str(rec.get("tool","")).upper()
            if tool not in tools:
                return False
        if s:
            hay = " ".join([
                str(rec.get("title","")),
                str(rec.get("rule_id","")),
                str(rec.get("file","")),
                str(rec.get("cwe","")),
                str(rec.get("tool","")),
                str(rec.get("severity","")),
            ]).lower()
            if s not in hay:
                return False
        return True

    def _resp(start_response, code:int, payload:dict):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        start_response(f"{code} OK" if code==200 else f"{code} NOT FOUND", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("Cache-Control","no-store"),
        ])
        return [body]

    def _wrapped(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/vsp/run_findings_preview_v1/"):
            return app(environ, start_response)

        # parse rid from path
        rid = path.split("/api/vsp/run_findings_preview_v1/", 1)[1].strip("/")
        qs = parse_qs(environ.get("QUERY_STRING","") or "")

        def q1(k, default=""):
            v = qs.get(k, [default])
            return v[0] if v else default

        try:
            limit = int(q1("limit","200") or "200")
        except Exception:
            limit = 200
        limit = max(1, min(limit, 2000))

        try:
            page = int(q1("page","1") or "1")
        except Exception:
            page = 1
        page = max(1, page)

        sev_q = (q1("sev","") or "").strip()
        tool_q = (q1("tool","") or "").strip()
        search = (q1("search","") or "").strip()

        sevs = set([x.strip().upper() for x in sev_q.split(",") if x.strip()]) if sev_q else set()
        tools = set([x.strip().upper() for x in tool_q.split(",") if x.strip()]) if tool_q else set()

        run_dir = _resolve(rid)
        if not run_dir:
            return _resp(start_response, 404, {
                "ok": False,
                "error": "run_not_found",
                "rid": rid,
                "has_findings": False,
                "total": 0,
                "items": [],
                "facets": {"severity": {}, "tool": {}},
            })

        run_dir = Path(run_dir)
        cand = [
            run_dir / "findings_unified.json",
            run_dir / "reports" / "findings_unified.json",
            run_dir / "findings_unified.csv",
            run_dir / "reports" / "findings_unified.csv",
        ]
        fp = next((x for x in cand if x.is_file() and x.stat().st_size>0), None)

        if not fp:
            # COMMERCIAL: stable schema, not an error that breaks UI
            return _resp(start_response, 200, {
                "ok": True,
                "has_findings": False,
                "warning": "findings_file_not_found",
                "rid": rid,
                "run_dir": str(run_dir),
                "file": None,
                "page": page,
                "limit": limit,
                "total": 0,
                "items": [],
                "facets": {"severity": {}, "tool": {}},
            })

        try:
            raw = _load_json_findings(fp) if fp.suffix.lower()==".json" else _load_csv_findings(fp)
        except Exception as e:
            return _resp(start_response, 200, {
                "ok": True,
                "has_findings": False,
                "warning": "findings_parse_error",
                "detail": str(e),
                "rid": rid,
                "run_dir": str(run_dir),
                "file": str(fp),
                "page": page,
                "limit": limit,
                "total": 0,
                "items": [],
                "facets": {"severity": {}, "tool": {}},
            })

        normed = []
        for r in raw:
            if not isinstance(r, dict):
                continue
            rec = _pick_fields(r)
            if _match(rec, sevs, tools, search):
                normed.append(rec)

        total = len(normed)
        start = (page-1)*limit
        end = start + limit
        items = normed[start:end]

        sev_counts = {}
        tool_counts = {}
        for rec in normed[:5000]:
            sv = str(rec.get("severity","")).upper() or "UNKNOWN"
            tl = str(rec.get("tool","")).upper() or "UNKNOWN"
            sev_counts[sv] = sev_counts.get(sv, 0) + 1
            tool_counts[tl] = tool_counts.get(tl, 0) + 1

        return _resp(start_response, 200, {
            "ok": True,
            "has_findings": True,
            "rid": rid,
            "run_dir": str(run_dir),
            "file": str(fp),
            "page": page,
            "limit": limit,
            "total": total,
            "items": items,
            "facets": {"severity": sev_counts, "tool": tool_counts},
        })

    return _wrapped
# === /VSP_WSGI_FINDINGS_PREVIEW_HANDLER_V2 ===

try:
    _APP = globals().get("application") or globals().get("app")
    if _APP is not None:
        globals()["application"] = _vsp_wsgi_findings_preview_v2(_APP)
except Exception:
    pass
'''

p.write_text(t + "\n" + BLOCK + "\n", encoding="utf-8")
print("[OK] appended WSGI findings preview handler v2")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile wsgi_vsp_ui_gateway.py"
echo "[DONE] Restart 8910 (no sudo) to apply."
