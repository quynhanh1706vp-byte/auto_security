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
