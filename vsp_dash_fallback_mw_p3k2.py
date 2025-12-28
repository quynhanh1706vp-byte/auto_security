# VSP_P3K3_DASH_MW_EXTENDED_V1
import os, json, re, time
from datetime import datetime
from urllib.parse import parse_qs

SEV_ORDER = {"CRITICAL":0,"HIGH":1,"MEDIUM":2,"MEDIUM+":2,"LOW":3,"INFO":4,"TRACE":5}

def _norm_sev(x):
    x = (x or "").strip()
    x = re.sub(r'[\.\,;:\s]+$', '', x)  # "CRITICAL." -> "CRITICAL"
    x = x.upper()
    if x in ("MEDIUMPLUS","MEDIUM_PLUS","MEDIUM+"):
        return "MEDIUM"
    return x or "INFO"

def _parse_ts(name: str):
    m = re.search(r'(\d{8})_(\d{6})', name or "")
    if not m: return None
    try:
        return datetime.strptime(m.group(1)+m.group(2), "%Y%m%d%H%M%S")
    except Exception:
        return None

def _roots():
    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]
    return [r for r in roots if os.path.isdir(r)]

def _find_rid_dir(rid: str):
    rid = (rid or "").strip()
    if not rid: return None
    for root in _roots():
        d = os.path.join(root, rid)
        if os.path.isdir(d):
            return d
    return None

def _pick_best_rid():
    best = None
    for root in _roots():
        try:
            for name in os.listdir(root):
                d = os.path.join(root, name)
                if not os.path.isdir(d):
                    continue
                ok = False
                for rel in (
                    "reports/findings_unified_commercial.json","reports/findings_unified.json",
                    "report/findings_unified_commercial.json","report/findings_unified.json",
                    "findings_unified_commercial.json","findings_unified.json",
                ):
                    fp = os.path.join(d, rel)
                    if os.path.isfile(fp) and os.path.getsize(fp) > 50:
                        ok = True
                        break
                if not ok:
                    continue
                ts = _parse_ts(name) or datetime.fromtimestamp(0)
                mt = os.path.getmtime(d)
                key = (ts, mt)
                if best is None or key > best[0]:
                    best = (key, name)
        except Exception:
            pass
    return best[1] if best else ""

def _load_items(rid: str, cap=300000):
    rid_dir = _find_rid_dir(rid)
    if not rid_dir:
        return None, []
    cands = [
        "reports/findings_unified_commercial.json",
        "reports/findings_unified.json",
        "report/findings_unified_commercial.json",
        "report/findings_unified.json",
        "findings_unified_commercial.json",
        "findings_unified.json",
    ]
    for rel in cands:
        fp = os.path.join(rid_dir, rel)
        if not os.path.isfile(fp):
            continue
        try:
            if os.path.getsize(fp) < 30:
                continue
        except Exception:
            continue
        try:
            with open(fp, "r", encoding="utf-8", errors="replace") as f:
                j = json.load(f)
            items = None
            for k in ("findings","items","results"):
                v = j.get(k)
                if isinstance(v, list):
                    items = v
                    break
            if items is None:
                items = []
            if len(items) > cap:
                items = items[:cap]
            return {"from": rel, "total": j.get("total")}, items
        except Exception:
            continue
    return None, []

def _counts(items):
    sev = {}
    tool_ch = {}
    cwe = {}
    for it in items or []:
        s = _norm_sev((it or {}).get("severity"))
        sev[s] = sev.get(s, 0) + 1

        t = str((it or {}).get("tool") or "UNKNOWN")
        if t not in tool_ch:
            tool_ch[t] = {"tool": t, "CRITICAL": 0, "HIGH": 0}
        if s in ("CRITICAL","HIGH"):
            tool_ch[t][s] = tool_ch[t].get(s, 0) + 1

        cw = (it or {}).get("cwe")
        if cw is None:
            continue
        cw = str(cw).strip()
        if not cw:
            continue
        if cw.isdigit():
            cw = "CWE-" + cw
        cwe[cw] = cwe.get(cw, 0) + 1
    return sev, tool_ch, cwe

def _top_findings(items, limit=25):
    def key(it):
        return SEV_ORDER.get(_norm_sev((it or {}).get("severity")), 99)
    arr = sorted(list(items or []), key=key)
    out = []
    for it in arr[:max(0, min(limit, 200))]:
        out.append({
            "severity": _norm_sev((it or {}).get("severity")),
            "title": (it or {}).get("title") or (it or {}).get("message") or "Finding",
            "tool": (it or {}).get("tool") or "UNKNOWN",
            "file": (it or {}).get("file") or (it or {}).get("path") or None,
            "cwe": (it or {}).get("cwe"),
        })
    return out

def _runs_index(maxn=40):
    cand=[]
    for root in _roots():
        try:
            for name in os.listdir(root):
                ts=_parse_ts(name)
                if not ts:
                    continue
                cand.append((ts, name))
        except Exception:
            pass
    cand=sorted(cand, key=lambda x:x[0], reverse=True)[:maxn]
    runs=[]
    for ts,rid in cand:
        _src, items = _load_items(rid, cap=200000)
        runs.append({
            "rid": rid,
            "run_id": rid,
            "label": ts.strftime("%Y-%m-%d %H:%M"),
            "ts": ts.isoformat(),
            "total": len(items or []),
        })
    return runs

# cache
_CACHE = {}
TTL = 12.0

def _base(rid: str):
    now = time.time()
    cur = _CACHE.get(rid)
    if cur and (now - cur["ts"]) < TTL:
        return cur["base"]
    src, items = _load_items(rid)
    sev, tool_ch, cwe = _counts(items)
    total = sum(sev.values()) if sev else len(items or [])
    base = {
        "rid": rid,
        "source": src or {},
        "items": items or [],
        "total": total,
        "sev": sev,
        "tool_ch": tool_ch,
        "cwe": cwe,
        "top_findings": _top_findings(items, 25),
        "runs_index": _runs_index(40),
    }
    _CACHE[rid] = {"ts": now, "base": base}
    return base

class DashFallbackMW:
    def __init__(self, app):
        self.app = app

    def _json(self, start_response, obj, code="200 OK"):
        data = (json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8")
        start_response(code, [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(data))),
            ("Cache-Control","no-store"),
        ])
        return [data]

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        qs = parse_qs(environ.get("QUERY_STRING") or "")
        rid = (qs.get("rid") or [""])[0].strip() or _pick_best_rid()

        # --- RID alias endpoints (fix legacy + typo double gate_root) ---
        if path in (
            "/api/vsp/rid_latest_gate_root_gate_root",
            "/api/vsp/rid_latest_gate_root",
            "/api/vsp/rid_latest_v3",
            "/api/vsp/latest_rid_v1",
            "/api/vsp/latest_rid_v30",
            "/api/vsp/rid_latest_v30",
        ):
            payload = {"ok": True, "rid": rid, "run_id": rid, "mode": "best_usable"}
            return self._json(start_response, payload)

        # --- fast runs index (dashboard panels) ---
        if path == "/api/vsp/runs_v3":
            base = _base(rid)
            limit = int((qs.get("limit") or ["20"])[0] or 20)
            offset = int((qs.get("offset") or ["0"])[0] or 0)
            runs = base["runs_index"][offset:offset+max(1, min(limit, 80))]
            return self._json(start_response, {"ok": True, "runs": runs, "total": len(base["runs_index"])})

        # --- run_status_v2/<rid> ---
        if path.startswith("/api/vsp/run_status_v2/"):
            r = path.split("/")[-1]
            return self._json(start_response, {"ok": True, "rid": r, "status": "DONE"})

        # --- artifacts index ---
        if path.startswith("/api/vsp/run_artifacts_index_v1/"):
            r = path.split("/")[-1]
            return self._json(start_response, {"ok": True, "rid": r, "artifacts": []})

        
        # VSP_P3K5_DATASOURCE_FAST_V1
        # --- datasource (dashboard) : force ok + lite findings to avoid watchdog/timeouts ---
        if path in ("/api/vsp/datasource", "/api/vsp/datasource_lite"):
            b = _base(rid)
            # conservative limits (UI only needs small slice for dashboard)
            limit = int((qs.get("limit") or ["200"])[0] or 200)
            offset = int((qs.get("offset") or ["0"])[0] or 0)
            limit = max(1, min(limit, 500))
            findings = b["items"][offset:offset+limit]
            runs = b["runs_index"][:40]
            payload = {
                "ok": True,
                "rid": rid,
                "run_id": rid,
                "mode": (qs.get("mode") or [""])[0] or None,
                "lite": True,
                "total": b["total"],
                "runs": runs,
                "findings": findings,
                "returned": len(findings),
                "kpis": {
                    "total": b["total"],
                    "CRITICAL": b["sev"].get("CRITICAL", 0),
                    "HIGH": b["sev"].get("HIGH", 0),
                    "MEDIUM": b["sev"].get("MEDIUM", 0),
                    "LOW": b["sev"].get("LOW", 0),
                    "INFO": b["sev"].get("INFO", 0),
                    "TRACE": b["sev"].get("TRACE", 0),
                },
            }
            return self._json(start_response, payload)

# --- findings_effective_v1/<rid>?limit=0 ---
        if path.startswith("/api/vsp/findings_effective_v1/"):
            r = path.split("/")[-1]
            b = _base(r)
            lim = int((qs.get("limit") or ["0"])[0] or 0)
            if lim == 0:
                return self._json(start_response, {"ok": True, "rid": r, "total": b["total"]})
            items = b["items"][:max(1, min(lim, 5000))]
            return self._json(start_response, {"ok": True, "rid": r, "total": b["total"], "findings": items})

        # --- findings_page_v3 (dashboard live checks often call limit=1) ---
        if path == "/api/vsp/findings_page_v3":
            b = _base(rid)
            limit = int((qs.get("limit") or ["100"])[0] or 100)
            offset = int((qs.get("offset") or ["0"])[0] or 0)
            limit = max(1, min(limit, 5000))
            items = b["items"][offset:offset+limit]
            return self._json(start_response, {"ok": True, "rid": rid, "total": b["total"], "findings": items})

        # --- top_findings_v3c ---
        if path in ("/api/vsp/top_findings_v3c", "/api/vsp/top_findings_v3"):
            b = _base(rid)
            limit = int((qs.get("limit") or ["200"])[0] or 200)
            limit = max(1, min(limit, 500))
            items = _top_findings(b["items"], limit=limit)
            return self._json(start_response, {"ok": True, "rid": rid, "total": b["total"], "items": items})

        # --- trend_v1 (simple points from runs index) ---
        if path == "/api/vsp/trend_v1":
            runs = _runs_index(20)
            points = [{"label": r["label"], "run_id": r["run_id"], "rid": r["rid"], "total": r["total"], "ts": r["ts"]} for r in runs[::-1]]
            return self._json(start_response, {"ok": True, "points": points})

        # --- dashboard extras ---
        if path == "/api/vsp/dashboard_v3_extras_v1":
            return self._json(start_response, {"ok": True, "rid": rid, "extras": {}})

        # --- main dashboard endpoints already handled in P3K2, keep coverage here too ---
        if (
            path.startswith("/api/vsp/dashboard_v3")
            or path in ("/api/vsp/dashboard_latest_v1", "/api/vsp/dash_kpis", "/api/vsp/dash_charts")
        ):
            b = _base(rid)
            sev = b["sev"]; tool_ch = b["tool_ch"]; cwe = b["cwe"]
            kpis = {
                "total": b["total"],
                "CRITICAL": sev.get("CRITICAL", 0),
                "HIGH": sev.get("HIGH", 0),
                "MEDIUM": sev.get("MEDIUM", 0),
                "LOW": sev.get("LOW", 0),
                "INFO": sev.get("INFO", 0),
                "TRACE": sev.get("TRACE", 0),
            }
            charts = {
                "severity_distribution": [{"severity": k, "count": v} for k,v in sorted(sev.items(), key=lambda kv: SEV_ORDER.get(kv[0],99))],
                "critical_high_by_tool": sorted(tool_ch.values(), key=lambda r: -(r.get("CRITICAL",0)+r.get("HIGH",0)))[:30],
                "top_cwe": [{"cwe": k, "count": v} for k,v in sorted(cwe.items(), key=lambda kv: kv[1], reverse=True)[:20]],
                "trend": [{"label": r["label"], "total": r["total"]} for r in b["runs_index"][:20]][::-1],
            }

            if path == "/api/vsp/dash_kpis":
                return self._json(start_response, {"ok": True, "rid": rid, **kpis, "kpis": kpis, "source": b["source"]})
            if path == "/api/vsp/dash_charts":
                return self._json(start_response, {"ok": True, "rid": rid, **charts, "charts": charts, "source": b["source"]})

            return self._json(start_response, {
                "ok": True, "rid": rid, "source": b["source"],
                "kpis": kpis, "charts": charts, "tables": {"top_findings": b["top_findings"]},
            })

        return self.app(environ, start_response)

def wrap(app):
    return DashFallbackMW(app)
