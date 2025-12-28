#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sed; need grep; need curl; need wc

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_fix_api_${TS}"
echo "[BACKUP] ${W}.bak_fix_api_${TS}"

mkdir -p tools out_ci/vsp_settings_v2 out_ci/rule_overrides_v2

# ---- 1) helper module: tools/vsp_tabs3_api_impl_v1.py ----
cat > tools/vsp_tabs3_api_impl_v1.py <<'PY'
# -*- coding: utf-8 -*-
from __future__ import annotations
from pathlib import Path
import json, time, re

UI_ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
OUT_ROOT = Path("/home/test/Data/SECURITY_BUNDLE/out")

SETTINGS_PATH = UI_ROOT / "out_ci" / "vsp_settings_v2" / "settings.json"
RULES_PATH    = UI_ROOT / "out_ci" / "rule_overrides_v2" / "rules.json"

SEV_ORDER = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]

def _now() -> int:
    return int(time.time())

def _read_json(p: Path, default):
    try:
        if not p.exists():
            return default
        return json.loads(p.read_text(encoding="utf-8", errors="replace") or "null") or default
    except Exception:
        return default

def _write_json(p: Path, obj):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")

def list_runs(limit: int = 50):
    items=[]
    if OUT_ROOT.exists():
        for d in sorted(OUT_ROOT.glob("RUN_*"), key=lambda x: x.stat().st_mtime, reverse=True):
            try:
                st = d.stat()
                items.append({"rid": d.name, "run_dir": str(d), "mtime": int(st.st_mtime)})
            except Exception:
                continue
            if len(items) >= limit:
                break
    return {"ok": True, "items": items, "limit": limit, "ts": _now()}

def _pick_run_dir(rid: str|None):
    if rid:
        d = OUT_ROOT / rid
        if d.exists():
            return d
    # fallback latest
    runs = list_runs(limit=1).get("items", [])
    if runs:
        return Path(runs[0]["run_dir"])
    return None

def _find_findings_file(run_dir: Path):
    candidates = [
        run_dir / "reports" / "findings_unified.json",
        run_dir / "findings_unified.json",
        run_dir / "report" / "findings_unified.json",
        run_dir / "reports" / "findings.json",
        run_dir / "findings.json",
    ]
    for p in candidates:
        if p.exists():
            return p
    return None

def _norm_sev(x):
    s = (x or "").strip().upper()
    if s in SEV_ORDER: return s
    # common aliases
    if s in ("CRIT",): return "CRITICAL"
    if s in ("WARN","WARNING"): return "LOW"
    if s in ("INFORMATIONAL",): return "INFO"
    return "INFO"

def _extract(obj):
    """
    Convert arbitrary finding record -> UI row with keys:
    severity, tool, rule, file, line, message
    """
    if not isinstance(obj, dict):
        return None
    tool = obj.get("tool") or obj.get("scanner") or obj.get("source") or obj.get("engine") or ""
    rule = obj.get("rule_id") or obj.get("rule") or obj.get("id") or obj.get("check_id") or obj.get("query") or ""
    msg  = obj.get("message") or obj.get("title") or obj.get("desc") or obj.get("description") or ""
    sev  = _norm_sev(obj.get("severity") or obj.get("level") or obj.get("impact") or obj.get("priority") or "")
    file = obj.get("file") or obj.get("path") or ""
    line = obj.get("line") or obj.get("start_line") or ""

    # nested locations (SARIF-like / semgrep-like)
    loc = obj.get("location") or obj.get("loc") or {}
    if isinstance(loc, dict):
        file = file or loc.get("path") or loc.get("file") or ""
        line = line or loc.get("line") or ""
        st = loc.get("start") or {}
        if isinstance(st, dict):
            line = line or st.get("line") or ""

    # ensure scalar
    def _s(v):
        if v is None: return ""
        if isinstance(v, (int,float)): return str(int(v))
        return str(v)

    return {
        "severity": sev,
        "tool": _s(tool),
        "rule": _s(rule),
        "file": _s(file),
        "line": _s(line),
        "message": _s(msg),
    }

def findings_query(rid: str|None, limit: int, offset: int, q: str, tool: str, severity: str):
    run_dir = _pick_run_dir(rid)
    items=[]
    counts={k:0 for k in SEV_ORDER}
    counts["TOTAL"]=0
    if not run_dir:
        return {"ok": True, "rid": rid or "", "run_dir": "", "items": [], "counts": counts, "limit": limit, "offset": offset, "q": q, "tool": tool, "severity": severity, "ts": _now()}

    fpath = _find_findings_file(run_dir)
    raw = []
    if fpath:
        data = _read_json(fpath, default=[])
        if isinstance(data, list):
            raw = data
        elif isinstance(data, dict):
            raw = data.get("items") or data.get("findings") or data.get("results") or []
            if not isinstance(raw, list):
                raw = []
    # normalize + filter
    q_l = (q or "").strip().lower()
    tool_l = (tool or "").strip().lower()
    sev_f = _norm_sev(severity) if (severity and severity.upper()!="ALL") else "ALL"

    norm=[]
    for r in raw:
        row = _extract(r)
        if not row:
            continue
        # counts first
        counts[row["severity"]] = counts.get(row["severity"],0) + 1
        counts["TOTAL"] += 1
        # filters
        if tool_l and tool_l not in row["tool"].lower():
            continue
        if sev_f != "ALL" and row["severity"] != sev_f:
            continue
        if q_l:
            blob = (row["tool"]+" "+row["rule"]+" "+row["file"]+" "+row["message"]).lower()
            if q_l not in blob:
                continue
        norm.append(row)

    # pagination
    total_after = len(norm)
    page = norm[offset: offset+limit] if limit > 0 else norm[offset:]
    return {
        "ok": True,
        "rid": run_dir.name,
        "run_dir": str(run_dir),
        "items": page,
        "counts": counts,
        "total_after_filter": total_after,
        "limit": limit,
        "offset": offset,
        "q": q,
        "tool": tool,
        "severity": severity,
        "ts": _now(),
    }

def settings_get():
    settings = _read_json(SETTINGS_PATH, default={})
    effective = {
        "degrade_graceful": True,
        "timeouts": {"kics_sec": 900, "trivy_sec": 900, "codeql_sec": 1800},
        "tools_enabled": {
            "bandit": True, "semgrep": True, "gitleaks": True, "kics": True,
            "trivy": True, "syft": True, "grype": True, "codeql": True
        }
    }
    return {"ok": True, "path": str(SETTINGS_PATH), "settings": settings, "effective": effective, "ts": _now()}

def settings_save(obj):
    if not isinstance(obj, dict):
        obj = {}
    _write_json(SETTINGS_PATH, obj)
    return {"ok": True, "path": str(SETTINGS_PATH), "settings": obj, "ts": _now()}

def rules_get():
    data = _read_json(RULES_PATH, default={})
    # accept either {"rules":[...]} or {"data":{"rules":[...]}}
    rules = []
    if isinstance(data, dict):
        if isinstance(data.get("rules"), list):
            rules = data["rules"]
        elif isinstance((data.get("data") or {}).get("rules"), list):
            rules = (data.get("data") or {}).get("rules") or []
    out = {"rules": rules}
    return {"ok": True, "path": str(RULES_PATH), "data": out, "ts": _now()}

def rules_save(obj):
    rules=[]
    if isinstance(obj, dict):
        if isinstance(obj.get("rules"), list):
            rules = obj["rules"]
        elif isinstance((obj.get("data") or {}).get("rules"), list):
            rules = (obj.get("data") or {}).get("rules") or []
    _write_json(RULES_PATH, {"rules": rules})
    return {"ok": True, "path": str(RULES_PATH), "data": {"rules": rules}, "ts": _now()}

def rules_apply_to_rid(rid: str):
    run_dir = _pick_run_dir(rid)
    if not run_dir:
        return {"ok": False, "error": "RID_NOT_FOUND", "rid": rid, "ts": _now()}
    rules = rules_get().get("data",{}).get("rules",[])
    outp = run_dir / "rule_overrides_applied.json"
    _write_json(outp, {"rid": run_dir.name, "applied_at": _now(), "rules": rules})
    return {"ok": True, "rid": run_dir.name, "run_dir": str(run_dir), "applied_path": str(outp), "rules_n": len(rules), "ts": _now()}
PY

# ---- 2) patch gateway: add missing /api/ui routes + harden /api 404 -> JSON ----
python3 - <<'PY'
from pathlib import Path
import time, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_TABS3_API_ROUTES_AND_API404_V1"
if marker in s:
    print("[OK] marker already present, skip append")
    raise SystemExit(0)

ts = time.strftime("%Y%m%d_%H%M%S")
bak = p.with_name(p.name + f".bak_before_append_{ts}")
bak.write_text(s, encoding="utf-8")
print("[BACKUP2]", bak)

append = r'''
# ============================================================
# VSP_P1_TABS3_API_ROUTES_AND_API404_V1
# - Ensure /api/ui/* routes exist (runs/findings/settings/rule_overrides/apply)
# - Ensure /api/* 404 returns JSON (no HTML injector)
# ============================================================
def _vsp__get_app_obj():
    try:
        return app  # type: ignore
    except Exception:
        pass
    try:
        return application  # type: ignore
    except Exception:
        pass
    return None

_vsp_app = _vsp__get_app_obj()
if _vsp_app:
    try:
        from flask import request, jsonify
    except Exception:
        request = None
        jsonify = None

    # --- harden 404 for /api/* ---
    try:
        @_vsp_app.errorhandler(404)
        def _vsp_api_404(e):  # noqa: F811
            try:
                path = (request.path if request else "")
            except Exception:
                path = ""
            if path.startswith("/api/"):
                payload = {"ok": False, "error": "HTTP_404_NOT_FOUND", "path": path, "ts": int(__import__("time").time())}
                return (jsonify(payload) if jsonify else ("Not Found", 404)), 404
            # keep existing behavior for non-api (simple)
            return ("Not Found", 404)
    except Exception as _e404:
        pass

    # --- add missing routes only (avoid duplicates) ---
    try:
        rules = {r.rule for r in _vsp_app.url_map.iter_rules()}
    except Exception:
        rules = set()

    def _add(rule, endpoint, view_func, methods):
        if rule in rules:
            return
        _vsp_app.add_url_rule(rule, endpoint=endpoint, view_func=view_func, methods=methods)

    try:
        from tools import vsp_tabs3_api_impl_v1 as _impl
    except Exception:
        _impl = None

    if _impl and request and jsonify:
        def _get_int(name, default):
            try:
                return int(request.args.get(name, default))
            except Exception:
                return default

        def _runs_v2():
            limit = _get_int("limit", 50)
            return jsonify(_impl.list_runs(limit=limit))

        def _findings_v2():
            rid = request.args.get("rid") or None
            limit = _get_int("limit", 50)
            offset = _get_int("offset", 0)
            q = request.args.get("q","")
            tool = request.args.get("tool","")
            severity = request.args.get("severity","ALL")
            return jsonify(_impl.findings_query(rid=rid, limit=limit, offset=offset, q=q, tool=tool, severity=severity))

        def _settings_v2():
            if request.method == "POST":
                obj = request.get_json(silent=True) or {}
                return jsonify(_impl.settings_save(obj))
            return jsonify(_impl.settings_get())

        def _rules_v2():
            if request.method == "POST":
                obj = request.get_json(silent=True) or {}
                return jsonify(_impl.rules_save(obj))
            return jsonify(_impl.rules_get())

        def _rules_apply_v2():
            obj = request.get_json(silent=True) or {}
            rid = obj.get("rid") or request.args.get("rid") or ""
            return jsonify(_impl.rules_apply_to_rid(str(rid)))

        _add("/api/ui/runs_v2", "vsp_ui_runs_v2", _runs_v2, ["GET"])
        _add("/api/ui/findings_v2", "vsp_ui_findings_v2", _findings_v2, ["GET"])
        _add("/api/ui/settings_v2", "vsp_ui_settings_v2", _settings_v2, ["GET","POST"])
        _add("/api/ui/rule_overrides_v2", "vsp_ui_rule_overrides_v2", _rules_v2, ["GET","POST"])
        _add("/api/ui/rule_overrides_apply_v2", "vsp_ui_rule_overrides_apply_v2", _rules_apply_v2, ["POST"])
# ============================================================
'''
p.write_text(s + "\n" + append, encoding="utf-8")
print("[OK] appended routes + api404 handler")
PY

echo "== py_compile =="
python3 -m py_compile tools/vsp_tabs3_api_impl_v1.py
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo "== restart service =="
sudo systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== verify endpoints now 200 JSON ok:true =="
curl -fsS "$BASE/api/ui/runs_v2?limit=1" | head -c 220; echo
curl -fsS "$BASE/api/ui/findings_v2?limit=1&offset=0" | head -c 260; echo
curl -fsS "$BASE/api/ui/settings_v2" | head -c 260; echo
curl -fsS "$BASE/api/ui/rule_overrides_v2" | head -c 260; echo

echo "[DONE] fix tabs3 api routes + api404"
