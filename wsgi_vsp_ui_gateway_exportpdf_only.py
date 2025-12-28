import os, glob, json, fnmatch
from urllib.parse import parse_qs, quote
import wsgi_vsp_ui_gateway as base

# ===================== COMMON =====================
def _now_iso():
    import datetime
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"

def _json(start_response, code:int, obj:dict, layer:str):
    body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    status = "200 OK" if code == 200 else f"{code} ERROR"
    start_response(status, [
        ("Content-Type","application/json"),
        ("Content-Length", str(len(body))),
        ("X-VSP-WSGI-LAYER", layer),
    ])
    return [body]

def _norm_sev(s):
    if s is None:
        return "INFO"
    x = str(s).strip().upper()
    m = {
        "CRITICAL":"CRITICAL","HIGH":"HIGH","MEDIUM":"MEDIUM","LOW":"LOW","INFO":"INFO","TRACE":"TRACE",
        "WARN":"LOW","WARNING":"LOW","ERROR":"MEDIUM","ERR":"MEDIUM","NOTE":"INFO","UNKNOWN":"INFO","NONE":"INFO"
    }
    return m.get(x, "INFO")

# ===================== OVERRIDES =====================
def _ovr_path():
    return os.environ.get("VSP_RULE_OVERRIDES_FILE") or "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/vsp_rule_overrides_v1.json"

def _load_ovr():
    path = _ovr_path()
    try:
        with open(path, "r", encoding="utf-8") as f:
            obj = json.load(f)
    except Exception:
        obj = {"version": 1, "updated_at": None, "items": []}
    if not isinstance(obj, dict):
        obj = {"version": 1, "updated_at": None, "items": []}
    obj.setdefault("version", 1)
    obj.setdefault("updated_at", None)
    obj.setdefault("items", [])
    if not isinstance(obj["items"], list):
        obj["items"] = []
    return obj

def _atomic_write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)

def _match_one(f, m):
    if not isinstance(m, dict):
        return False
    for k in ("rule_id","tool","cwe"):
        if m.get(k):
            if str(f.get(k,"")) != str(m.get(k,"")):
                return False
    pg = m.get("path_glob")
    if pg:
        path = f.get("path") or f.get("file") or f.get("filename") or ""
        if not fnmatch.fnmatch(path, pg):
            return False
    mc = m.get("message_contains")
    if mc:
        msg = f.get("message") or f.get("title") or ""
        if str(mc).lower() not in str(msg).lower():
            return False
    return True

def _apply_overrides(items, overrides, show_suppressed=False):
    applied = {"suppressed": 0, "downgraded": 0}
    out = []
    for f in (items or []):
        if not isinstance(f, dict):
            out.append(f); continue

        f["severity_norm"] = _norm_sev(f.get("severity") or f.get("severity_norm") or f.get("level"))
        suppressed = False

        for r in overrides.get("items", []) or []:
            if not isinstance(r, dict):
                continue
            if not _match_one(f, r.get("match", {}) or {}):
                continue

            act = (r.get("action") or "").lower().strip()
            if act == "suppress":
                suppressed = True
                f["suppressed"] = True
                f["override_action"] = "suppress"
                f["override_id"] = r.get("id")
                f["override_justification"] = r.get("justification")
                applied["suppressed"] += 1
                break

            if act == "downgrade":
                newsev = _norm_sev(r.get("set_severity") or "INFO")
                if f.get("severity_norm") != newsev:
                    f["severity_orig"] = f.get("severity_norm")
                    f["severity_norm"] = newsev
                    f["override_action"] = "downgrade"
                    f["override_id"] = r.get("id")
                    f["override_justification"] = r.get("justification")
                    applied["downgraded"] += 1

        if suppressed and not show_suppressed:
            continue
        out.append(f)
    return out, applied

# ===================== CI RESOLVE =====================
def _norm_rid(rid: str) -> str:
    rid = (rid or "").strip()
    return rid[4:] if rid.startswith("RUN_") else rid

def _ci_root():
    return os.environ.get("VSP_CI_OUT_ROOT") or "/home/test/Data/SECURITY-10-10-v4/out_ci"

def _resolve_ci_dir(rid: str) -> str:
    rn = _norm_rid(rid)
    root = _ci_root()
    cand = os.path.join(root, rn)
    if os.path.isdir(cand):
        return cand
    for d in sorted(glob.glob(os.path.join(root, "VSP_CI_*")), reverse=True):
        if rn in os.path.basename(d):
            return d
    return ""

def _latest_ci_dir():
    root = _ci_root()
    cands = [d for d in glob.glob(os.path.join(root, "VSP_CI_*")) if os.path.isdir(d)]
    best = ""
    best_m = -1.0
    for d in cands:
        try:
            m = os.path.getmtime(d)
        except Exception:
            continue
        if m > best_m:
            best_m = m
            best = d
    return best

def _pick_latest(paths):
    best = ""
    best_m = -1.0
    for f in paths:
        try:
            m = os.path.getmtime(f)
        except Exception:
            continue
        if m > best_m:
            best_m = m
            best = f
    return best

def _pick_pdf(ci_dir: str) -> str:
    cands = []
    for pat in (os.path.join(ci_dir, "reports", "*.pdf"), os.path.join(ci_dir, "*.pdf")):
        cands.extend(glob.glob(pat))
    cands = [f for f in cands if os.path.isfile(f)]
    return _pick_latest(cands)

def _pick_findings(ci_dir: str) -> str:
    cands = [
        os.path.join(ci_dir, "reports", "findings_unified.json"),
        os.path.join(ci_dir, "findings_unified.json"),
    ]
    cands += glob.glob(os.path.join(ci_dir, "reports", "findings_unified*.json"))
    cands += glob.glob(os.path.join(ci_dir, "findings_unified*.json"))
    cands = [f for f in cands if os.path.isfile(f)]
    return _pick_latest(cands)

def _pick_summary(ci_dir: str) -> str:
    cands = [
        os.path.join(ci_dir, "reports", "summary_unified.json"),
        os.path.join(ci_dir, "summary_unified.json"),
    ]
    cands += glob.glob(os.path.join(ci_dir, "reports", "summary_unified*.json"))
    cands += glob.glob(os.path.join(ci_dir, "summary_unified*.json"))
    cands = [f for f in cands if os.path.isfile(f)]
    return _pick_latest(cands)

# ===================== DASH DATA BUILD =====================
def _count_by_sev(items):
    out = {k:0 for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]}
    for f in items or []:
        if not isinstance(f, dict):
            continue
        out[_norm_sev(f.get("severity_norm") or f.get("severity") or f.get("level"))] += 1
    return out

def _count_by_tool(items):
    out = {}
    for f in items or []:
        if not isinstance(f, dict):
            continue
        tool = str(f.get("tool") or "UNKNOWN").strip()
        out[tool] = out.get(tool, 0) + 1
    return dict(sorted(out.items(), key=lambda kv: kv[1], reverse=True))

def _top_cwe(items):
    out = {}
    for f in items or []:
        if not isinstance(f, dict):
            continue
        cwe = f.get("cwe")
        if not cwe:
            continue
        cwe = str(cwe).strip()
        out[cwe] = out.get(cwe, 0) + 1
    if not out:
        return None, 0
    k = max(out, key=out.get)
    return k, out[k]

def _score(by_sev):
    # simple CIO-ish score (commercial baseline)
    score = 100.0
    score -= by_sev.get("CRITICAL",0) * 25.0
    score -= by_sev.get("HIGH",0) * 10.0
    score -= by_sev.get("MEDIUM",0) * 5.0
    score -= by_sev.get("LOW",0) * 2.0
    score -= by_sev.get("INFO",0) * 0.5
    # TRACE no penalty
    if score < 0: score = 0.0
    return int(round(score))

def _drill_links(rid):
    # drilldown via findings_preview filters (WSGI-preempted, stable)
    base = f"/api/vsp/findings_preview_v1/{quote(rid)}"
    links = {
        "all": f"{base}?limit=200",
        "suppressed": f"{base}?show_suppressed=1&limit=200",
        "severity": {s: f"{base}?sev={s}&limit=200" for s in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]},
    }
    return links

def _build_dashboard(ci_dir: str, rid: str):
    fpath = _pick_findings(ci_dir) if ci_dir else ""
    items = []
    if fpath:
        try:
            raw = json.load(open(fpath, "r", encoding="utf-8"))
            if isinstance(raw, dict):
                items = raw.get("items") if isinstance(raw.get("items"), list) else raw.get("findings") if isinstance(raw.get("findings"), list) else []
            elif isinstance(raw, list):
                items = raw
        except Exception:
            items = []

    overrides = _load_ovr()
    items2, applied = _apply_overrides(items, overrides, show_suppressed=True)

    by_sev = _count_by_sev(items2)
    by_tool = _count_by_tool(items2)
    top_tool = next(iter(by_tool.items()), (None, 0))
    top_cwe, top_cwe_n = _top_cwe(items2)

    obj = {
        "ok": True,
        "rid": rid,
        "ci_run_dir": ci_dir or None,
        "file_findings": fpath or None,
        "kpi": {
            "total_findings": sum(by_sev.values()),
            "security_score": _score(by_sev),
            "top_tool": {"name": top_tool[0], "count": top_tool[1]},
            "top_cwe": {"id": top_cwe, "count": top_cwe_n},
        },
        "by_severity": by_sev,
        "by_tool": by_tool,
        "rule_overrides": {"updated_at": overrides.get("updated_at"), "applied": applied},
        "links": _drill_links(rid),
        "updated_at": _now_iso(),
    }
    return obj

# ===================== APP =====================
class CommercialPreemptApp:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "").strip()
        method = (environ.get("REQUEST_METHOD") or "GET").upper().strip()
        q = parse_qs(environ.get("QUERY_STRING", "") or "")

        # (1) Rule Overrides API
        if path == "/api/vsp/rule_overrides_v1":
            try:
                if method == "GET":
                    return _json(start_response, 200, _load_ovr(), "RULE_OVERRIDES_V1")
                if method == "POST":
                    try:
                        length = int(environ.get("CONTENT_LENGTH") or "0")
                    except Exception:
                        length = 0
                    raw = (environ.get("wsgi.input").read(length) if length > 0 else b"") or b"{}"
                    obj = json.loads(raw.decode("utf-8", errors="ignore") or "{}")
                    if not isinstance(obj, dict):
                        raise ValueError("invalid_json")
                    obj.setdefault("version", 1)
                    obj.setdefault("items", [])
                    if not isinstance(obj["items"], list):
                        raise ValueError("items_must_be_list")
                    norm_items = []
                    for it in obj["items"]:
                        if not isinstance(it, dict):
                            continue
                        action = (it.get("action") or "").lower().strip()
                        if action not in ("suppress","downgrade"):
                            continue
                        just = (it.get("justification") or "").strip()
                        if not just:
                            continue
                        match = it.get("match") or {}
                        if not isinstance(match, dict):
                            match = {}
                        out = {
                            "id": it.get("id") or f"ovr_{int(__import__('time').time()*1000)}",
                            "match": match,
                            "action": action,
                            "justification": just,
                            "expires_at": it.get("expires_at") or None,
                        }
                        if action == "downgrade":
                            out["set_severity"] = _norm_sev(it.get("set_severity") or "INFO")
                        norm_items.append(out)
                    obj["items"] = norm_items
                    obj["updated_at"] = _now_iso()
                    _atomic_write(_ovr_path(), obj)
                    return _json(start_response, 200, obj, "RULE_OVERRIDES_V1")
                return _json(start_response, 405, {"ok": False, "error": "METHOD_NOT_ALLOWED"}, "RULE_OVERRIDES_V1")
            except Exception as e:
                return _json(start_response, 500, {"ok": False, "error": "RULE_OVERRIDES_ERR", "detail": str(e)}, "RULE_OVERRIDES_V1")

        # (2) Export PDF
        if path.startswith("/api/vsp/run_export_v3/"):
            fmt = (q.get("fmt", ["html"])[0] or "html").lower().strip()
            # === EXPORT_HEAD_SUPPORT_V1 ===
            # UI commercial probes export availability via HEAD; serve headers only.
            if method == "HEAD":
                rid = path.split("/api/vsp/run_export_v3/", 1)[1].strip("/")
                ci_dir = _resolve_ci_dir(rid)
                fmt2 = fmt or "html"
                if fmt2 == "pdf":
                    pdf = _pick_pdf(ci_dir) if ci_dir else ""
                    if pdf and os.path.isfile(pdf):
                        start_response("200 OK", [
                            ("Content-Type","application/pdf"),
                            ("X-VSP-EXPORT-AVAILABLE","1"),
                            ("X-VSP-EXPORT-FILE", os.path.basename(pdf)),
                            ("X-VSP-WSGI-LAYER","EXPORTPDF_ONLY"),
                        ])
                        return [b""]
                    start_response("200 OK", [
                        ("Content-Type","application/json"),
                        ("X-VSP-EXPORT-AVAILABLE","0"),
                        ("X-VSP-WSGI-LAYER","EXPORTPDF_ONLY"),
                    ])
                    return [b""]
                start_response("200 OK", [
                    ("Content-Type","application/json"),
                    ("X-VSP-EXPORT-AVAILABLE","1"),
                    ("X-VSP-WSGI-LAYER","EXPORTPROBE_HEAD_V1"),
                ])
                return [b""]
            if fmt == "pdf":
                rid = path.split("/api/vsp/run_export_v3/", 1)[1].strip("/")
                ci_dir = _resolve_ci_dir(rid)
                pdf = _pick_pdf(ci_dir) if ci_dir else ""
                if pdf and os.path.isfile(pdf):
                    size = os.path.getsize(pdf)
                    start_response("200 OK", [
                        ("Content-Type", "application/pdf"),
                        ("Content-Disposition", f'attachment; filename="{os.path.basename(pdf)}"'),
                        ("Content-Length", str(size)),
                        ("X-VSP-EXPORT-AVAILABLE", "1"),
                        ("X-VSP-EXPORT-FILE", os.path.basename(pdf)),
                        ("X-VSP-WSGI-LAYER", "EXPORTPDF_ONLY"),
                    ])
                    return open(pdf, "rb")
                return _json(start_response, 404, {"ok": False, "http_code": 404, "error": "PDF_NOT_FOUND", "ci_run_dir": ci_dir or None}, "EXPORTPDF_ONLY")

        # (3) Findings preview (PREEMPT + filters)
        if path.startswith("/api/vsp/findings_preview_v1/") and method == "GET":
            rid = path.split("/api/vsp/findings_preview_v1/", 1)[1].strip("/")
            ci_dir = _resolve_ci_dir(rid)

            # filters
            sev_f = (q.get("sev",[None])[0] or "").strip().upper() or None
            tool_f = (q.get("tool",[None])[0] or "").strip() or None
            cwe_f = (q.get("cwe",[None])[0] or "").strip() or None
            show_supp = (q.get("show_suppressed", ["0"])[0] or "0").strip().lower() in ("1","true","yes","on")

            limit = q.get("limit", [None])[0]
            try:
                limit_n = int(limit) if limit else None
            except Exception:
                limit_n = None

            fpath = _pick_findings(ci_dir) if ci_dir else ""
            if not fpath:
                obj = {
                    "ok": True, "rid": rid, "ci_run_dir": ci_dir or None,
                    "has_findings": False, "total": 0, "items_n": 0,
                    "warning": "findings_file_not_found", "file": None, "items": [],
                    "rule_overrides": {"updated_at": _load_ovr().get("updated_at"), "applied": {"suppressed": 0, "downgraded": 0}, "show_suppressed": show_supp},
                }
                return _json(start_response, 200, obj, "FINDINGS_PREEMPT_V2")

            try:
                raw = json.load(open(fpath, "r", encoding="utf-8"))
            except Exception as e:
                return _json(start_response, 500, {"ok": False, "error": "FINDINGS_PARSE_FAILED", "file": fpath, "detail": str(e)}, "FINDINGS_PREEMPT_V2")

            if isinstance(raw, dict):
                items = raw.get("items") if isinstance(raw.get("items"), list) else raw.get("findings") if isinstance(raw.get("findings"), list) else []
            elif isinstance(raw, list):
                items = raw
            else:
                items = []

            total = len(items)
            if limit_n is not None:
                items = items[:limit_n]

            overrides = _load_ovr()
            # apply overrides first (so severity_norm reflects downgrade)
            items2, applied = _apply_overrides(items, overrides, show_suppressed=show_supp)

            # apply filters after overrides
            def keep(f):
                if not isinstance(f, dict): return True
                if sev_f and _norm_sev(f.get("severity_norm")) != sev_f: return False
                if tool_f and str(f.get("tool") or "") != tool_f: return False
                if cwe_f and str(f.get("cwe") or "") != cwe_f: return False
                return True

            items3 = [f for f in items2 if keep(f)]

            obj = {
                "ok": True, "rid": rid, "ci_run_dir": ci_dir or None,
                "has_findings": len(items3) > 0,
                "total": total, "items_n": len(items3),
                "file": fpath, "items": items3,
                "rule_overrides": {"updated_at": overrides.get("updated_at"), "applied": applied, "show_suppressed": show_supp},
            }
            return _json(start_response, 200, obj, "FINDINGS_PREEMPT_V2")

        # (4) Dashboard data (latest + per-rid)
        if path == "/api/vsp/dashboard_latest_v1" and method == "GET":
            ci_dir = _latest_ci_dir()
            rid = os.path.basename(ci_dir) if ci_dir else ""
            obj = _build_dashboard(ci_dir, rid) if ci_dir else {"ok": False, "error": "NO_CI_DIR"}
            return _json(start_response, 200, obj, "DASH_LATEST_V1")

        if path.startswith("/api/vsp/dashboard_data_v1/") and method == "GET":
            rid = path.split("/api/vsp/dashboard_data_v1/", 1)[1].strip("/")
            ci_dir = _resolve_ci_dir(rid)
            obj = _build_dashboard(ci_dir, rid)
            return _json(start_response, 200, obj, "DASH_DATA_V1")

        # default passthrough
        return self.inner(environ, start_response)

_inner = getattr(base, "application", None) or getattr(base, "app", None)
application = CommercialPreemptApp(_inner)

try:
    print("[VSP_WSGI_COMMERCIAL] installed (overrides + exportpdf + findings_v2 + dashdata)")
except Exception:
    pass
